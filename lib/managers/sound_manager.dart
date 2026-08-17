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
/// | `bgm.mp3`             | 로비 배경음악(루프)  | https://kenney.nl/assets/music-jingles                          |
/// | `dungeon_bgm.mp3`     | 던전 배경음악(루프)  | https://kenney.nl/assets/music-jingles (다른 트랙)               |
/// | `hit.wav`             | 일반 타격음         | https://kenney.nl/assets/impact-sounds                          |
/// | `critical.wav`        | 크리티컬 타격음(둔탁)| https://kenney.nl/assets/rpg-audio                               |
/// | `coin.wav`            | 골드 획득음         | https://kenney.nl/assets/interface-sounds                       |
/// | `gacha_reveal.wav`    | 가챠 결과 확인음    | https://kenney.nl/assets/ui-audio                                |
///
/// 이 매니저는 위 6개 파일이 `assets/audio/`에 이미 존재한다고 가정하고
/// 짜여 있다 — 실제 mp3/wav를 내려받아 그 폴더에 넣고 `pubspec.yaml`의
/// `assets/audio/` 선언(이미 추가돼 있음)만 확인하면 바로 재생된다.
class SoundManager {
  SoundManager._internal();

  static final SoundManager instance = SoundManager._internal();

  static const List<String> _sfxFiles = [
    'hit.wav',
    'critical.wav',
    'coin.wav',
    'gacha_reveal.wav',
  ];

  bool sfxEnabled = true;
  bool bgmEnabled = true;

  String? _currentBgmFile;

  /// main()이 앱 시작 시 한 번 호출 — SFX를 미리 캐시에 올려 첫 재생
  /// 지연(디스크/네트워크 로드)을 없앤다. 실패해도(파일 없음 등) 조용히
  /// 넘어간다 — 이후 개별 재생 호출들도 각자 try/catch로 보호돼 있다.
  Future<void> init() async {
    try {
      await FlameAudio.audioCache.loadAll(_sfxFiles);
    } catch (error) {
      debugPrint('[SoundManager] SFX 프리로드 실패(assets/audio/ 파일을 확인하세요): $error');
    }
  }

  Future<void> playLobbyBgm() => _playBgm('bgm.mp3');

  Future<void> playDungeonBgm() => _playBgm('dungeon_bgm.mp3');

  Future<void> _playBgm(String file) async {
    if (!bgmEnabled || _currentBgmFile == file) {
      return;
    }
    try {
      await FlameAudio.bgm.play(file, volume: 0.5);
      _currentBgmFile = file;
    } catch (error) {
      debugPrint('[SoundManager] BGM 재생 실패($file): $error');
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
  Future<void> playHit() => _playSfx('hit.wav');

  /// 크리티컬 타격 — 일반 타격음보다 더 둔탁한 별도 사운드.
  Future<void> playCritical() => _playSfx('critical.wav');

  /// 골드 획득 — 몬스터 처치/오프라인 보상 등 골드가 쏟아질 때.
  Future<void> playCoin() => _playSfx('coin.wav');

  /// 가챠 결과 확인 — [GachaRevealScreen]이 카드가 뒤집히는 순간 호출한다.
  Future<void> playGachaReveal() => _playSfx('gacha_reveal.wav');

  Future<void> _playSfx(String file) async {
    if (!sfxEnabled) {
      return;
    }
    try {
      await FlameAudio.play(file);
    } catch (error) {
      debugPrint('[SoundManager] SFX 재생 실패($file): $error');
    }
  }
}
