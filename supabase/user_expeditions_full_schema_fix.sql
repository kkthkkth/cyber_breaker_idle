-- 버그: user_expeditions 테이블 컬럼이 하나씩 없다고 계속 터짐 —
-- 처음엔 "column user_expeditions.unit_ids does not exist"(42703),
-- 그 다음엔 "column user_expeditions.start_time does not exist"(42703).
--
-- 원인: 운영 DB의 user_expeditions 테이블이 클라이언트가 기대하는 스키마
-- (lib/models/expedition_model.dart의 ExpeditionMission.toJson/fromJson,
-- lib/managers/supabase_manager.dart의 fetchUserExpeditions/
-- syncExpeditionStart/syncExpeditionCollected)보다 훨씬 이전 버전으로
-- 만들어져 있던 것으로 보입니다 — 컬럼이 하나씩 빠진 채로요. 이전에
-- unit_ids만 추가하는 마이그레이션(user_expeditions_unit_ids_fix.sql)을
-- 실행했지만 start_time도 없다는 걸 뒤늦게 알게 됐습니다. 이 파일이 그
-- 마이그레이션을 대체합니다 — 클라이언트 모델이 실제로 쓰는 컬럼을 전부
-- 한 번에, 몇 번을 실행해도 안전하게(멱등) 추가합니다.
--
-- [주의] ExpeditionMission.toJson()/fromJson()을 직접 확인했습니다 —
-- 클라이언트가 실제로 읽고 쓰는 컬럼은 정확히 아래 5개뿐입니다
-- (user_id, region_id, unit_ids, start_time, is_collected). end_time/
-- status/rewards 같은 컬럼은 클라이언트 어디에도 없습니다 — 종료 시각은
-- start_time + 지역별 소요시간(하드코딩된
-- ExpeditionCatalog.regions[].duration)으로 매번 계산하고, 보상도 같은
-- 카탈로그에서 가져오지 DB에 저장하지 않습니다. 그래서 없는 컬럼을
-- 추측으로 추가하지 않고, 실제로 필요한 5개만 정확히 맞췄습니다 —
-- 안 쓰는 컬럼을 만들어 두면 나중에 헷갈리는 원인만 됩니다.

-- 1) 테이블이 아예 없다면 최종 스키마로 생성.
create table if not exists user_expeditions (
  user_id uuid not null references auth.users(id) on delete cascade,
  region_id text not null,
  unit_ids text[] not null default '{}',
  start_time timestamptz not null default now(),
  is_collected boolean not null default false,
  primary key (user_id, region_id)
);

-- 2) 테이블은 있지만 일부 컬럼만 빠진 경우 — 하나씩 또 터지는 일이 없게
-- 클라이언트가 쓰는 5개 컬럼 전부를 각각 확인해서 없는 것만 추가한다.
-- (이미 있는 컬럼은 조용히 건너뛰므로 몇 번을 실행해도 안전하다.)
alter table user_expeditions
  add column if not exists user_id uuid references auth.users(id) on delete cascade;
alter table user_expeditions
  add column if not exists region_id text;
alter table user_expeditions
  add column if not exists unit_ids text[] not null default '{}';
alter table user_expeditions
  add column if not exists start_time timestamptz not null default now();
alter table user_expeditions
  add column if not exists is_collected boolean not null default false;

-- 3) user_id/region_id는 위 2)에서 방금 추가됐을 수도 있어 not null
-- 제약이 없을 수 있다 — 기존 행이 있어도 안전하게(NULL 값이 없는 경우만)
-- not null로 맞춘다. 혹시 NULL이 섞인 오래된 행이 있으면 이 구문만
-- 실패하니, 그 행들을 먼저 정리한 뒤 다시 실행하면 된다.
do $$
begin
  if not exists (
    select 1 from information_schema.columns
    where table_name = 'user_expeditions' and column_name = 'user_id' and is_nullable = 'NO'
  ) then
    alter table user_expeditions alter column user_id set not null;
  end if;
  if not exists (
    select 1 from information_schema.columns
    where table_name = 'user_expeditions' and column_name = 'region_id' and is_nullable = 'NO'
  ) then
    alter table user_expeditions alter column region_id set not null;
  end if;
end $$;

-- 4) 기본키(user_id, region_id)가 없다면 추가 — syncExpeditionStart의
-- upsert(onConflict: 'user_id, region_id')가 이 제약에 의존한다.
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'user_expeditions'::regclass and contype = 'p'
  ) then
    alter table user_expeditions add primary key (user_id, region_id);
  end if;
end $$;

-- 5) RLS/정책 — 이미 걸려 있다면 drop 후 재생성해도 결과가 같으므로
-- 안전하게 다시 실행 가능하다.
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
