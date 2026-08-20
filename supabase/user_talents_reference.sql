-- user_talents 테이블 + profiles.talent_points 컬럼 — 특성(별자리) 트리
-- 진행도 동기화가 정확히 이 스키마를 가정합니다
-- (lib/managers/supabase_manager.dart의 fetchTalentPoints/updateTalentPoints/
-- fetchUserTalents/syncUserTalent).
--
-- 이미 두 가지를 세팅해 두셨다면, 아래 컬럼명과 정확히 일치하는지만
-- 확인해 주세요 — 다르면 이 SQL을 실행하지 말고 대신
-- lib/managers/supabase_manager.dart의 네 메서드만 실제 컬럼명에 맞게
-- 고치면 됩니다.
--
-- 노드 카탈로그(트리 구조 자체: id/이름/선행 조건/버프 등)는 서버 테이블이
-- 아니라 lib/managers/talent_manager.dart의 _defaultTalentTree()에
-- 하드코딩돼 있습니다(요구사항: "테스트용으로 4개 정도의 하드코딩된 트리
-- 구조") — 이 테이블은 오직 "유저가 어느 노드를 몇 레벨까지 찍었는지"
-- 진행도만 저장합니다.
--
-- 플러터 쪽 호출부:
--   fetchTalentPoints(): profiles.select('talent_points').eq('id', userId)
--   updateTalentPoints(points): profiles.update({'talent_points': points}).eq('id', userId)
--   fetchUserTalents(): user_talents.select('node_id, level').eq('user_id', userId)
--   syncUserTalent(nodeId, level): user_talents.upsert({user_id, node_id, level},
--                                                        onConflict: 'user_id, node_id')

alter table profiles add column if not exists talent_points integer not null default 0;

create table if not exists user_talents (
  user_id uuid not null references auth.users(id) on delete cascade,
  node_id text not null,
  level integer not null default 0,
  primary key (user_id, node_id)
);

alter table user_talents enable row level security;

drop policy if exists "user_talents_select_own" on user_talents;
drop policy if exists "user_talents_upsert_own" on user_talents;
drop policy if exists "user_talents_update_own" on user_talents;

create policy "user_talents_select_own" on user_talents
  for select using (auth.uid() = user_id);
create policy "user_talents_upsert_own" on user_talents
  for insert with check (auth.uid() = user_id);
create policy "user_talents_update_own" on user_talents
  for update using (auth.uid() = user_id);
