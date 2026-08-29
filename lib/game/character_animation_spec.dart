import 'package:flame/components.dart' show Vector2;

/// 캐릭터 하나의 모션(run/attack/wait) 하나를 그리는 스프라이트 시트
/// 규격 — Supabase `character_animations` 테이블의 행 하나를 그대로 옮겨
/// 담은 것([CharacterAnimationManager.fetchSpec] 참고). [amount]/
/// [textureSize]/[stepTime] 전부 DB 값이 그대로 출처이므로, 이 프로젝트
/// 어디에도(Flame 컴포넌트든 이 데이터 클래스든) 캐릭터별 프레임 수·칸
/// 크기를 코드로 하드코딩하지 않는다 — 새 캐릭터가 추가되면 DB에 행만
/// 추가하면 되고, 배포(코드 빌드) 없이도 즉시 반영된다.
class SpriteSheetSpec {
  const SpriteSheetSpec({
    required this.sheetPath,
    required this.amount,
    required this.textureSize,
    required this.stepTime,
  });

  /// `character_animations` 행 하나(Supabase가 돌려주는 `Map<String,
  /// dynamic>`)를 파싱한다. 숫자 컬럼은 Postgres 드라이버가 `int`/`double`
  /// 어느 쪽으로 역직렬화하든 안전하도록 `num`으로 받아 명시적으로
  /// 변환한다(`frame_width`/`frame_height`가 정수 컬럼이어도 JSON 왕복
  /// 과정에서 double로 올 수 있다).
  factory SpriteSheetSpec.fromRow(Map<String, dynamic> row) {
    return SpriteSheetSpec(
      sheetPath: row['sheet_path'] as String,
      amount: (row['frame_count'] as num).toInt(),
      textureSize: Vector2(
        (row['frame_width'] as num).toDouble(),
        (row['frame_height'] as num).toDouble(),
      ),
      stepTime: (row['step_time'] as num).toDouble(),
    );
  }

  /// R2 objectKey(DB의 `sheet_path` 컬럼 그대로) — [RemoteSpriteLoader
  /// .loadSpriteAnimation]이 이 값을 [StorageManager]에 넘겨 프리사인드
  /// URL을 발급받는다. 이 클래스 자신은 URL 발급에 관여하지 않는다.
  final String sheetPath;

  /// 시트 전체 프레임 수(`frame_count`).
  final int amount;

  /// 시트 한 칸(프레임 하나)의 픽셀 크기(`frame_width`/`frame_height`) —
  /// 시트 전체 크기를 프레임 수로 나눠 역산하지 않고 DB 값을 그대로 쓴다.
  final Vector2 textureSize;

  /// 프레임 하나당 재생 시간(초, `step_time`) — 공격 모션은
  /// [PlayerAnimationComponent.computeAttackStepTime]이 공속 기반으로 이
  /// 값을 덮어쓰므로 실제로는 무시된다(그 외 모션은 이 값 그대로 쓰인다).
  final double stepTime;
}

/// 캐릭터 한 명의 스프라이트 시트 규격 모음 — DB `state` 컬럼('run'/
/// 'attack'/'wait') 값을 키로 하는 조회 테이블이다. 이 프로젝트의 다른
/// 모든 코드([AppImages.playerActionFrame]/[playerActionAnimation] 등)와
/// 동일하게 "대기 모션"을 가리키는 문자열은 항상 'wait'다 — Flame 쪽
/// [PlayerState.idle](이 애니메이션을 재생하는 컴포넌트 상태의 이름)과
/// 헷갈리지 않도록 주의한다. 세 상태가 전부 있어야만 유효한 게 아니라,
/// 마이그레이션이 상태별로 부분적으로 진행돼(예: run만 시트로 먼저
/// 올리고 attack/wait은 아직 예전 방식) 일부만 등록돼 있어도 그대로
/// 동작한다 — 등록 안 된 상태는 [PlayerAnimationComponent]가 기존
/// webp/PNG 프레임 경로로 조용히 대체한다([operator []]이 없으면 null을
/// 돌려주는 것으로 충분).
class CharacterAnimationSpec {
  const CharacterAnimationSpec(this._byState);

  /// 완전히 빈 규격 — DB 조회가 실패했거나(오프라인 등) 이 캐릭터가 아직
  /// 테이블에 전혀 등록되지 않았을 때 쓴다. 모든 상태 조회가 null을
  /// 돌려주므로 [PlayerAnimationComponent]는 항상 기존 경로로 대체한다.
  static const CharacterAnimationSpec empty = CharacterAnimationSpec({});

  final Map<String, SpriteSheetSpec> _byState;

  /// [state]("run"/"attack"/"wait")에 해당하는 규격 — DB에 그 상태 행이
  /// 없으면 null.
  SpriteSheetSpec? operator [](String state) => _byState[state];
}
