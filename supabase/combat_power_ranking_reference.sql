-- 참고용 재구성본 — 실제 라이브 `get_combat_power_ranking` 함수의 원본
-- SQL이 이 저장소에 커밋돼 있지 않아(코드 주석에서만 참조됨), 코드베이스에
-- 이미 있는 문서(SupabaseManager.fetchCombatPowerRanking 주석)를 근거로
-- 다시 구성했습니다. 실제 함수 정의와 다를 수 있으니, 그대로 실행하지
-- 마시고 기존 함수에서 SELECT 절/RETURNS TABLE에 `equipped_character`
-- 컬럼 하나만 추가해 주세요 — 이 파일은 그 변경을 반영한 전체 모습의
-- 예시입니다.
--
-- 이 변경이 필요한 이유: 전투력 랭킹(RankingCategory.combatPower)만
-- 이 RPC를 거치는데, RankingEntry.equippedCharacter가 null로만 채워지고
-- 있어(ranking_model.dart 참고) 랭킹 화면 1~100위 아바타가 전투력 탭에서만
-- 기본 아이콘으로 보입니다. 챕터·환생/무한의 탑 탭은 이미 일반
-- .select()라서 별도 작업 없이 정상 반영됩니다.

create or replace function get_combat_power_ranking(result_limit integer default 100)
returns table (
  id uuid,
  nickname text,
  combat_power integer,
  equipped_character text  -- 추가된 컬럼
)
language sql
security definer
as $$
  select p.id, p.nickname, p.combat_power, p.equipped_character
  from profiles p
  where not exists (
    select 1 from ranking_blacklist b where b.user_id = p.id
  )
  order by p.combat_power desc
  limit result_limit;
$$;
