-- user_expeditions 테이블 — 용병 파견/탐험(Expedition) 진행도 동기화가
-- 정확히 이 스키마를 가정합니다(lib/managers/supabase_manager.dart의
-- fetchUserExpeditions/syncExpeditionStart/syncExpeditionCollected).
--
-- 이미 테이블을 세팅해 두셨다면, 아래 컬럼명과 정확히 일치하는지만
-- 확인해 주세요 — 다르면 이 SQL을 실행하지 말고 대신
-- lib/managers/supabase_manager.dart의 세 메서드만 실제 컬럼명에 맞게
-- 고치면 됩니다.
--
-- 지역 카탈로그(지역 id/이름/소요 시간/요구 인원/보상 등)는 서버 테이블이
-- 아니라 lib/models/expedition_model.dart의 ExpeditionCatalog.regions에
-- 하드코딩돼 있습니다(요구사항: "테스트용 지역 2~3개를 하드코딩") — 이
-- 테이블은 오직 "유저가 어느 지역에 누구를 보냈고 언제 끝나며 수령했는지"
-- 진행도만 저장합니다. 유저당 지역 하나에 동시에 임무 1개만 허용되므로
-- (user_id, region_id)가 자연스러운 기본키/upsert 충돌 키입니다.
--
-- 플러터 쪽 호출부:
--   fetchUserExpeditions(): select('region_id, unit_ids, start_time, is_collected')
--                                    .eq('user_id', userId)
--   syncExpeditionStart(...): upsert({user_id, region_id, unit_ids, start_time,
--                                      is_collected: false}, onConflict: 'user_id, region_id')
--   syncExpeditionCollected(regionId): update({'is_collected': true})
--                                        .eq('user_id', userId).eq('region_id', regionId)

create table if not exists user_expeditions (
  user_id uuid not null references auth.users(id) on delete cascade,
  region_id text not null,
  unit_ids text[] not null default '{}',
  start_time timestamptz not null,
  is_collected boolean not null default false,
  primary key (user_id, region_id)
);

alter table user_expeditions enable row level security;

drop policy if exists "user_expeditions_select_own" on user_expeditions;
drop policy if exists "user_expeditions_upsert_own" on user_expeditions;
drop policy if exists "user_expeditions_update_own" on user_expeditions;

create policy "user_expeditions_select_own" on user_expeditions
  for select using (auth.uid() = user_id);
create policy "user_expeditions_upsert_own" on user_expeditions
  for insert with check (auth.uid() = user_id);
create policy "user_expeditions_update_own" on user_expeditions
  for update using (auth.uid() = user_id);
