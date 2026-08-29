import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../game/character_animation_spec.dart';
import '../utils/master_character_id.dart';

/// Supabase `character_animations` 테이블(캐릭터별 run/attack/wait
/// 스프라이트 시트 메타데이터 — `character_id`, `state`, `sheet_path`,
/// `frame_count`, `frame_width`, `frame_height`, `step_time`)을 조회해
/// [CharacterAnimationSpec]으로 반환하는 싱글턴.
///
/// [주의: R2 URL 발급은 이 매니저의 책임이 아니다] 여기서 반환하는
/// [SpriteSheetSpec.sheetPath]는 R2 objectKey일 뿐, 실제 프리사인드 URL로
/// 바꾸는 일은 [RemoteSpriteLoader.loadSpriteAnimation]이 내부적으로
/// [StorageManager]를 호출해 처리한다(그 함수가 이미 이 프로젝트의 다른
/// 모든 원격 이미지 로딩과 같은 경로를 타므로, 여기서 중복으로 URL을
/// 발급받지 않는다) — 이 매니저는 순수하게 "이 캐릭터의 시트 규격이
/// 무엇인지"만 안다.
///
/// [캐릭터를 코드 배포 없이 추가/변경할 수 있는 이유] 프레임 수·칸
/// 크기·시트 경로가 전부 이 테이블의 행으로 존재하므로, 새 캐릭터를
/// 추가하거나 기존 캐릭터의 시트를 교체할 때 Supabase에 행만
/// 추가/수정하면 된다 — Flutter 코드에는 어떤 캐릭터가 몇 프레임인지
/// 하드코딩된 곳이 전혀 없다.
///
/// [주의: characterId는 gradeBadgeLabel, DB 조회 키는 별도로 변환된다]
/// [fetchSpec]이 받는 [characterId]는 이 프로젝트 전역에서 쓰는
/// [Equipment.gradeBadgeLabel] 형식("N1")이다 — 실제 `character_animations
/// .character_id` 컬럼 값("char_n1")과는 명명 규칙이 달라서, 내부적으로
/// [masterCharacterId]를 거쳐 변환한 뒤 쿼리한다(자세한 이유는 그 함수
/// 문서 참고 — `CharacterMetaManager.attackTypeFor`/
/// `CharacterMetadataManager.byId`도 같은 변환을 같은 함수로 공유한다).
/// 호출부는 이 변환을 신경 쓸 필요 없이 항상 gradeBadgeLabel 그대로
/// 넘기면 된다.
class CharacterAnimationManager {
  CharacterAnimationManager._internal();

  static final CharacterAnimationManager instance = CharacterAnimationManager._internal();

  static const String _table = 'character_animations';

  SupabaseClient get _client => Supabase.instance.client;

  /// characterId별로 조회 결과를 세션 동안 캐싱한다 — 캐릭터 스위칭을
  /// 반복해도(무기 교체, 캐릭터 탭 미리보기 등) 이미 조회한 캐릭터는
  /// 매번 DB를 다시 두드리지 않는다. 이 테이블은 게임 콘텐츠 메타데이터라
  /// 세션 중에 값이 바뀔 일이 없다고 가정한다(값이 바뀌면 앱 재시작으로
  /// 반영— [StorageManager]의 서명 URL 캐시처럼 시간에 따라 스스로
  /// 낡는 데이터가 아니다).
  final Map<String, CharacterAnimationSpec> _cache = {};

  /// 같은 characterId를 여러 곳(전투 화면 + 캐릭터 미리보기 등)이 거의
  /// 동시에 요청하면, 이미 진행 중인 조회의 Future를 그대로 공유해 같은
  /// 쿼리를 중복으로 보내지 않는다([StorageManager._pendingRequests]와
  /// 동일한 관례).
  final Map<String, Future<CharacterAnimationSpec>> _pendingRequests = {};

  /// [characterId]의 스프라이트 시트 규격을 조회한다 — 실패하면(오프라인,
  /// 테이블 미생성, 아직 이 캐릭터가 시트로 마이그레이션되지 않아 행이
  /// 하나도 없는 경우 등) [CharacterAnimationSpec.empty]를 반환한다. 이
  /// 함수는 절대 예외를 던지지 않는다 — 호출부([PlayerAnimationComponent
  /// .loadCharacter])가 빈 규격을 "이 캐릭터/상태는 아직 시트가 없다"는
  /// 뜻으로 받아들여 기존 webp/PNG 프레임 경로로 조용히 대체한다.
  ///
  /// [디버깅용 로그] 매 호출마다 캐시/진행 중 요청/새 조회 중 어느
  /// 경로를 탔는지 로그로 남긴다 — 캐릭터가 계속 레거시 경로로 폴백될 때,
  /// 콘솔에서 "쿼리가 아예 안 나가는지(캐시된 빈 규격을 계속 재사용 중)"
  /// 와 "쿼리는 나가는데 실패/빈 응답인지"를 구분할 수 있게 하기 위함
  /// ([_fetchAndCache] 문서 참고 — 실제 원인 분석 로그는 그쪽에 있다).
  Future<CharacterAnimationSpec> fetchSpec(String characterId) {
    final String masterId = masterCharacterId(characterId);
    final CharacterAnimationSpec? cached = _cache[characterId];
    if (cached != null) {
      debugPrint(
        '[CharacterAnimationManager] $characterId($masterId) 캐시 사용 — DB를 다시 조회하지 않습니다.',
      );
      return Future.value(cached);
    }

    final Future<CharacterAnimationSpec>? inFlight = _pendingRequests[characterId];
    if (inFlight != null) {
      debugPrint('[CharacterAnimationManager] $characterId($masterId) 이미 진행 중인 조회에 합류합니다.');
      return inFlight;
    }

    debugPrint('[CharacterAnimationManager] $characterId($masterId) 새 조회를 시작합니다.');
    final Future<CharacterAnimationSpec> request = _fetchAndCache(characterId, masterId);
    _pendingRequests[characterId] = request;
    return request;
  }

  /// [_table]에서 [masterId](이미 [masterCharacterId]로 변환된 값)의 행을
  /// 조회한다 — 이 함수가 [fetchSpec]의 실제 네트워크 왕복을 전담한다.
  ///
  /// [디버깅용 로그] 아래 세 경로를 서로 다른 문구로 명확히 구분해서
  /// 찍는다 — 캐릭터가 계속 레거시 PNG 프레임(`player_n1_wait1.png` 등)
  /// 으로 폴백될 때, 콘솔만 보고 "① 쿼리 자체가 예외로 실패했는지(RLS
  /// 정책/네트워크/테이블 미생성 등), ② 쿼리는 성공했는데 0행이 돌아왔는지
  /// (character_id/state 값이 실제 DB 데이터와 안 맞는 경우), ③ 정상적으로
  /// 몇 행을 받았는지"를 바로 구분할 수 있게 하기 위함이다:
  /// - [PostgrestException]은 Supabase/PostgREST가 요청 자체를 거부했을 때
  ///   (RLS 정책 위반, 권한 없음, 테이블 없음 등)만 던져지는 타입이라 별도로
  ///   잡아서 `code`/`message`/`details`/`hint`를 전부 그대로 찍는다 —
  ///   `code`가 `42501`이면 RLS SELECT 정책 또는 `authenticated`/`anon`
  ///   롤의 테이블 GRANT가 없다는 뜻이고(`supabase/
  ///   character_animations_reference.sql`의 grant/policy 구문이 실제로
  ///   적용됐는지 확인), `42P01`이나 `PGRST205`류는 테이블 자체가 아직
  ///   생성되지 않았다는 뜻이다.
  /// - 그 외 예외(네트워크 단절 등)는 타입/메시지/스택트레이스를 그대로
  ///   찍는다.
  /// - 예외 없이 성공했지만 0행이면, RLS/네트워크 문제가 **아니라는** 것과
  ///   실제 조회에 쓰인 [masterId]를 명시해서, "혹시 character_id 값이
  ///   DB에 실제로 있는 값과 다른 게 아닐까"를 바로 의심할 수 있게 한다.
  Future<CharacterAnimationSpec> _fetchAndCache(String characterId, String masterId) async {
    try {
      final List<dynamic> rows = await _client
          .from(_table)
          .select('state, sheet_path, frame_count, frame_width, frame_height, step_time')
          .eq('character_id', masterId);

      if (rows.isEmpty) {
        debugPrint(
          '[CharacterAnimationManager] $masterId 조회 성공했지만 0행입니다 — RLS/네트워크 '
          '문제는 아닙니다. Supabase 대시보드에서 character_animations 테이블에 '
          "character_id='$masterId'인 행이 실제로 있는지, 있다면 state 컬럼 값이 "
          "'run'/'attack'/'wait' 중 하나가 맞는지 확인하세요.",
        );
      } else {
        final String states = rows
            .map((dynamic row) => (row as Map<String, dynamic>)['state'])
            .join(', ');
        debugPrint('[CharacterAnimationManager] $masterId 조회 성공 — ${rows.length}행 (state: $states)');
      }

      final Map<String, SpriteSheetSpec> byState = {
        for (final dynamic row in rows)
          (row as Map<String, dynamic>)['state'] as String: SpriteSheetSpec.fromRow(row),
      };
      final CharacterAnimationSpec spec = CharacterAnimationSpec(byState);
      // 실패가 아니라 "행이 0개"인 정상 응답도 캐싱한다 — 이 캐릭터는
      // 아직 시트로 마이그레이션되지 않았다는 사실 자체가 세션 중에 바뀌지
      // 않으므로, 매번 다시 조회해서 매번 빈 결과를 받을 이유가 없다.
      // 캐시 키는(DB 조회 키인 master id가 아니라) 호출부가 넘긴
      // gradeBadgeLabel 그대로 쓴다 — [fetchSpec]의 캐시 조회도 같은
      // 키로 이뤄지기 때문이다.
      _cache[characterId] = spec;
      return spec;
    } on PostgrestException catch (error) {
      debugPrint(
        '[CharacterAnimationManager] $masterId 조회 실패(PostgrestException) — '
        'code=${error.code}, message=${error.message}, details=${error.details}, '
        'hint=${error.hint}. code=42501이면 RLS SELECT 정책 또는 authenticated/anon '
        '롤의 테이블 GRANT 누락, 42P01/PGRST205류면 테이블이 아직 없다는 뜻입니다 — '
        'supabase/character_animations_reference.sql이 이 Supabase 프로젝트에 정확히 '
        '적용됐는지 확인하세요.',
      );
      // 조회 자체가 실패한 경우(인프라/권한 문제)는 캐싱하지 않는다 —
      // "행이 없다"와 달리 다음 로드에서 복구됐을 때 다시 시도할 기회를 준다.
      return CharacterAnimationSpec.empty;
    } catch (error, stackTrace) {
      debugPrint(
        '[CharacterAnimationManager] $masterId 조회 중 예상치 못한 오류'
        '(${error.runtimeType}): $error\n$stackTrace',
      );
      return CharacterAnimationSpec.empty;
    } finally {
      _pendingRequests.remove(characterId);
    }
  }
}
