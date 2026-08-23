import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/foundation.dart';

/// BGM 루프 + SFX 재생을 담당하는 싱글턴 — [FlameAudio](내부적으로
/// audioplayers)를 감싼다. 모든 재생 호출을 try/catch로 감싸서, 사운드
/// 파일이 아직 없거나(assets/audio/ 준비 전) 로드에 실패해도 게임플레이
/// 자체는 절대 죽지 않는다(이 프로젝트의 다른 매니저들이 Supabase 실패를
/// 다루는 것과 같은 관례).
///
/// ## 필요한 에셋 (`assets/audio/`)
/// 아래 6개 파일이 이 경로에 있어야 실제 소리가 난다 — 상업적 이용까지
/// 가능한 무료 오픈소스 사운드로 채우려면 Kenney.nl(전부 CC0, 출처 표기도
/// 필요 없음)을 추천한다:
///
/// | 파일                  | 용도                | 추천 팩(Kenney.nl)                                              |
/// |-----------------------|--------------------|-----------------------------------------------------------------|
/// | `bgm.ogg`             | 로비 배경음악(루프)  | https://kenney.nl/assets/music-jingles                          |
/// | `dungeon_bgm.ogg`     | 던전 배경음악(루프)  | https://kenney.nl/assets/music-jingles (다른 트랙)               |
/// | `hit.ogg`             | 일반 타격음         | https://kenney.nl/assets/impact-sounds                          |
/// | `critical.ogg`        | 크리티컬 타격음(둔탁)| https://kenney.nl/assets/rpg-audio                               |
/// | `coin.ogg`            | 골드 획득음         | https://kenney.nl/assets/interface-sounds                       |
/// | `gacha_reveal.ogg`    | 가챠 결과 확인음    | https://kenney.nl/assets/ui-audio                                |
///
/// [주의] 파일명은 `.ogg`지만 실제로는 Ogg 컨테이너(매직 바이트 `OggS`)다 —
/// 예전엔 이 6개 파일이 전부 `.mp3` 확장자를 달고 있었는데 내용물은 그대로
/// Ogg였다. 데스크톱/모바일의 `audioplayers` 백엔드는 컨테이너를 스니핑해서
/// 재생하는 경우가 많아 눈치채기 어려웠지만, 웹의 `<audio>` 엘리먼트는
/// 확장자/MIME 타입으로 디코더를 고정해 버려서 매번 `MEDIA_ELEMENT_ERROR:
/// Format error`로 재생이 실패했다(웹에서 SFX/BGM이 전혀 안 들리던 원인).
/// 파일 내용을 다시 인코딩하지 않고 확장자만 실제 포맷에 맞게 `.ogg`로
/// 바로잡아 해결했다 — Chrome/Firefox는 Ogg Vorbis를 `<audio>`로 네이티브
/// 재생한다.
///
/// 이 매니저는 위 6개 파일이 `assets/audio/`에 이미 존재한다고 가정하고
/// 짜여 있다 — 실제 오디오를 내려받아 그 폴더에 넣고 `pubspec.yaml`의
/// `assets/audio/` 선언(이미 추가돼 있음)만 확인하면 바로 재생된다.
class SoundManager {
  SoundManager._internal();

  static final SoundManager instance = SoundManager._internal();

  static const List<String> _sfxFiles = [
    'hit.ogg',
    'critical.ogg',
    'coin.ogg',
    'gacha_reveal.ogg',
  ];

  bool sfxEnabled = true;
  bool bgmEnabled = true;

  String? _currentBgmFile;

  /// 한 번이라도 재생/프리로드에 실패한 파일명(SFX든 BGM이든 공용) —
  /// 웹에서 특정 wav 인코딩이 `MEDIA_ERR_SRC_NOT_SUPPORTED`(Format error
  /// Code 4)처럼 디코딩 자체가 불가능한 경우, 매번 다시 시도해봐야 항상
  /// 같은 이유로 또 실패할 뿐이다 — 한 번 실패를 확인한 파일은 이후
  /// 호출에서 아예 건드리지 않고 조용히 넘어가서, 전투 중 반복 재생되는
  /// SFX(타격음 등) 때문에 매 프레임 같은 에러 로그가 도배되거나 불필요한
  /// 재생 시도가 반복되는 것을 막는다.
  final Set<String> _brokenFiles = {};

  /// main()이 앱 시작 시 한 번 호출 — SFX를 미리 캐시에 올려 첫 재생
  /// 지연(디스크/네트워크 로드)을 없앤다. 파일 하나씩 개별 try/catch로
  /// 로드한다 — [FlameAudio.audioCache.loadAll]에 통째로 맡기면 그중
  /// 하나라도 포맷이 깨져 있을 때 나머지 정상 파일까지 프리로드가
  /// 통째로 실패할 수 있다(배치 Future 하나가 통째로 reject). 실패한
  /// 파일은 [_brokenFiles]에 바로 등록해 첫 재생 시도조차 하지 않는다.
  Future<void> init() async {
    // audioplayers(flame_audio가 감싸는 실제 재생 엔진)는 디코딩 실패
    // (예: 에셋이 아직 준비 안 된 자리표시 파일이라 "Format error Code: 4")를
    // 우리 Future의 예외로 던지는 게 아니라, 자체 AudioLogger가 내부에서
    // 곧바로 print()로 빨간 스택트레이스를 찍는다 — 그래서 이 파일의 모든
    // try/catch로도 막을 수 없었다(진짜 원인). 로그 레벨을 none으로
    // 낮추면 그 내부 print 자체가 나가지 않는다 — 우리 쪽
    // debugPrint('[SoundManager] ...')는 그대로 남아 무엇이 실패했는지는
    // 계속 알 수 있다.
    AudioLogger.logLevel = AudioLogLevel.none;

    for (final String file in _sfxFiles) {
      try {
        await FlameAudio.audioCache.load(file);
      } catch (error) {
        _brokenFiles.add(file);
        debugPrint('[SoundManager] SFX 프리로드 실패($file, 이후 재생 생략): $error');
      }
    }
  }

  Future<void> playLobbyBgm() => _playBgm('bgm.ogg');

  Future<void> playDungeonBgm() => _playBgm('dungeon_bgm.ogg');

  Future<void> _playBgm(String file) async {
    if (!bgmEnabled || _currentBgmFile == file || _brokenFiles.contains(file)) {
      return;
    }
    try {
      await FlameAudio.bgm.play(file, volume: 0.5);
      _currentBgmFile = file;
    } catch (error) {
      _brokenFiles.add(file);
      debugPrint('[SoundManager] BGM 재생 실패($file, 이후 재생 생략): $error');
    }
  }

  Future<void> stopBgm() async {
    _currentBgmFile = null;
    try {
      await FlameAudio.bgm.stop();
    } catch (error) {
      debugPrint('[SoundManager] BGM 정지 실패: $error');
    }
  }

  /// 일반(비크리티컬) 타격 — [IdleGame._resolveHit].
  Future<void> playHit() => _playSfx('hit.ogg');

  /// 크리티컬 타격 — 일반 타격음보다 더 둔탁한 별도 사운드.
  Future<void> playCritical() => _playSfx('critical.ogg');

  /// 골드 획득 — 몬스터 처치/오프라인 보상 등 골드가 쏟아질 때.
  Future<void> playCoin() => _playSfx('coin.ogg');

  /// 가챠 결과 확인 — [GachaRevealScreen]이 카드가 뒤집히는 순간 호출한다.
  Future<void> playGachaReveal() => _playSfx('gacha_reveal.ogg');

  Future<void> _playSfx(String file) async {
    if (!sfxEnabled || _brokenFiles.contains(file)) {
      return;
    }
    try {
      await FlameAudio.play(file);
    } catch (error) {
      // 웹 오디오 포맷 비호환 등으로 재생 자체가 불가능한 파일은 여기서
      // 회로를 끊는다 — 전투 중 초당 여러 번 호출되는 타격음이 매번
      // 똑같은 이유로 실패하며 로그를 도배하는 것을 막는다.
      _brokenFiles.add(file);
      debugPrint('[SoundManager] SFX 재생 실패($file, 이후 재생 생략): $error');
    }
  }
}
