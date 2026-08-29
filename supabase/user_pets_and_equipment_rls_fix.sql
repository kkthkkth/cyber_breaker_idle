-- 버그: 브라우저 콘솔에 다음 두 에러가 계속 반복해서 찍힘 —
-- [SupabaseManager] 펫 목록 동기화 실패:
--   PostgrestException(message: new row violates row-level security policy
--   (USING expression) for table "user_pets", code: 42501)
-- [SupabaseManager] 장비 목록 동기화 실패:
--   PostgrestException(message: new row violates row-level security policy
--   (USING expression) for table "user_equipment", code: 42501)
--
-- [이전 버전과 다른 점] 이전에 준 마이그레이션(RLS 정책 4개)이 이미 실행됐어야
-- 하는데도 같은 에러가 그대로 재현된다면, 원인은 둘 중 하나다:
--   (a) 이 SQL 자체가 실제로 실행되지 않았다(다른 Supabase 프로젝트의 SQL
--       Editor에서 실행했거나, 실행 중 에러가 나서 뒷부분이 적용 안 됐거나 등).
--   (b) RLS 정책은 맞게 들어갔지만, 그 밑단의 테이블 권한(GRANT)이 아예
--       없어서 `authenticated` 롤 자체가 이 테이블을 건드릴 자격이 없다.
--       RLS 정책은 "이미 권한이 있는 요청 중 어떤 행을 볼 수 있는지"만
--       걸러주는 필터라, GRANT 없이는 정책이 다 맞아도 무조건 막힌다 —
--       "정책은 맞는 것 같은데 여전히 403"인 사례의 상당수가 이 GRANT 누락
--       때문이다. 그래서 이번 버전은 정책뿐 아니라 GRANT까지 명시적으로
--       다시 부여한다(이미 있어도 재실행 안전).
-- 이 파일을 Supabase 대시보드 → SQL Editor에서 처음부터 끝까지 그대로
-- 실행하면 된다(여러 번 실행해도 안전 — 전부 idempotent).
--
-- 플러터 쪽 호출부(lib/managers/supabase_manager.dart):
--   fetchUserPets()/fetchUserEquipment(): select('id, data').eq('user_id', userId)
--   syncUserPets(pets)/syncUserEquipment(items):
--     upsert([{'id':..., 'user_id':..., 'data':...}], onConflict: 'id')
--     + 남은 id만 골라 delete().eq('user_id', userId).inFilter('id', staleIds)
-- 컬럼명/타입이 아래(id, user_id, data)와 정확히 일치해야 합니다.

-- ── user_pets ──────────────────────────────────────────────────────
create table if not exists user_pets (
  id text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  data jsonb not null
);

alter table user_pets enable row level security;

drop policy if exists "user_pets_select_own" on user_pets;
drop policy if exists "user_pets_upsert_own" on user_pets;
drop policy if exists "user_pets_update_own" on user_pets;
drop policy if exists "user_pets_delete_own" on user_pets;
drop policy if exists "user_pets_all_own" on user_pets;

-- select/insert/update/delete를 각각 별도 정책으로 두는 대신 for all
-- 하나로 합친다 — upsert(INSERT ... ON CONFLICT DO UPDATE)는 내부적으로
-- INSERT/UPDATE 양쪽 경로를 다 타고, PostgREST가 결과를 돌려주려면
-- (RETURNING) SELECT 권한도 필요하다 — 네 종류를 따로따로 관리하다가
-- 하나라도 빠지면 바로 이런 42501이 재현되므로, "내 user_id인 행은
-- 뭐든 다 허용"으로 단순화해 빠뜨릴 여지를 없앤다.
create policy "user_pets_all_own" on user_pets
  for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- [핵심] RLS 정책은 "이미 테이블 권한이 있는 요청을 필터링"할 뿐이다 —
-- authenticated 롤에 테이블 자체 권한(GRANT)이 없으면 정책이 전부 맞아도
-- 무조건 거부된다. Supabase 프로젝트 대부분은 public 스키마의 새 테이블에
-- 이 권한을 자동으로 안 붙여주는 경우가 있어(생성 경로에 따라 다름),
-- 명시적으로 다시 부여한다(이미 있어도 재실행 안전).
grant usage on schema public to authenticated, anon;
grant select, insert, update, delete on user_pets to authenticated;

-- ── user_equipment ────────────────────────────────────────────────
create table if not exists user_equipment (
  id text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  data jsonb not null
);

alter table user_equipment enable row level security;

drop policy if exists "user_equipment_select_own" on user_equipment;
drop policy if exists "user_equipment_upsert_own" on user_equipment;
drop policy if exists "user_equipment_update_own" on user_equipment;
drop policy if exists "user_equipment_delete_own" on user_equipment;
drop policy if exists "user_equipment_all_own" on user_equipment;

create policy "user_equipment_all_own" on user_equipment
  for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

grant select, insert, update, delete on user_equipment to authenticated;

-- ── 실행 후 검증(선택) ────────────────────────────────────────────────
-- 아래 두 쿼리를 SQL Editor에서 따로 실행해 실제로 반영됐는지 눈으로
-- 확인할 수 있다:
--
-- 1) 정책이 정확히 이 두 테이블에 있는지:
--   select tablename, policyname, cmd, qual, with_check
--   from pg_policies
--   where tablename in ('user_pets', 'user_equipment');
--
-- 2) authenticated 롤에 실제 테이블 권한이 있는지:
--   select table_name, grantee, privilege_type
--   from information_schema.role_table_grants
--   where table_name in ('user_pets', 'user_equipment')
--     and grantee = 'authenticated';
--
-- 위 두 쿼리 중 하나라도 결과가 비어 있으면, 이 SQL이 실제로 이 프로젝트에
-- 적용되지 않은 것이다(Supabase 대시보드 좌측 상단에서 프로젝트가
-- lib/constants/supabase_config.dart의 SupabaseConfig.url/anonKey가
-- 가리키는 프로젝트와 일치하는지부터 다시 확인할 것 — 계정에 프로젝트가
-- 여러 개면 SQL Editor를 다른 프로젝트에서 열어 실행했을 가능성이 가장
-- 흔한 원인이다).
