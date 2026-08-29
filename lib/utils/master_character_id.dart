/// [Equipment.gradeBadgeLabel] 형식(예: "N1")을 Supabase `characters`
/// 마스터 테이블(및 그 `character_id`를 참조하는 `character_animations`/
/// `character_metadata` 등 다른 테이블들)이 실제로 쓰는 DB ID 형식(예:
/// "char_n1")으로 변환한다.
///
/// [배경] 이 프로젝트는 캐릭터를 가리키는 두 가지 ID 체계를 함께 쓴다 —
/// 장비/에셋 경로 전역([AppImages] 등)은 `Equipment.gradeBadgeLabel`
/// ("N1")을 쓰지만, DB의 `characters` 마스터 테이블과 그걸 참조하는
/// 테이블들은 "char_" 접두어 + 소문자("char_n1")를 쓴다. 두 체계를 그대로
/// 동일시해서 DB를 조회/비교하면 조건이 항상 어긋나면서도 예외 없이
/// 조용히 빗나가는 버그가 여러 매니저에서 반복됐다(캐릭터 애니메이션이
/// 매번 레거시 경로로 폴백되거나, 공격 타입이 항상 기본값 melee로만
/// 떨어지거나, 캐릭터 기본 스탯이 항상 0으로 계산되는 등) — 변환 지점을
/// 이 함수 하나로 통일해 같은 실수가 새 매니저에서 또 반복되지 않게 한다.
///
/// [호출부 규약] 이 함수는 "DB에 실제로 쿼리/비교를 보내기 직전"에만
/// 호출한다 — 매니저의 공개 API(예: `CharacterAnimationManager.fetchSpec`,
/// `CharacterMetaManager.attackTypeFor`, `CharacterMetadataManager.byId`)는
/// 여전히 gradeBadgeLabel을 그대로 받는다. 그래야 [IdleGame]/[GameManager]
/// 같은 호출부가 지금까지처럼 `Equipment.gradeBadgeLabel`(또는
/// `_equippedCharacterId`)을 그대로 넘기면 되고, 캐릭터 스위칭/사거리
/// 판정 등 기존 전투 로직 호출부를 하나도 고칠 필요가 없다.
///
/// 변환 규칙은 다른 등급(R/SR/SSR/SSSR 등)도 "char_" + 소문자 규칙을
/// 그대로 따른다고 가정한다("N1" → "char_n1") — 마스터 테이블 쪽 명명
/// 규칙이 이후 이 패턴과 달라지면 이 함수 하나만 고치면 모든 호출부에
/// 한 번에 반영된다.
String masterCharacterId(String gradeBadgeLabel) => 'char_${gradeBadgeLabel.toLowerCase()}';
