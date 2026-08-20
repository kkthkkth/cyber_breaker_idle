-- user_equipment 테이블 — 장비 서버 동기화(SupabaseManager.syncUserEquipment/
-- fetchUserEquipment)가 정확히 이 스키마를 가정합니다.
--
-- 참고: 이 섹션은 supabase/trade_reference.sql의 "1. 일반 장비 서버 동기화"
-- 부분과 완전히 동일합니다 — 그 파일을 나중에(또는 이미) 실행하셨다면
-- 이 파일은 건너뛰거나, 실행하셔도 아래처럼 create table/policy 모두
-- 재실행 안전(idempotent)하게 만들어 뒀으니 중복 실행해도 에러가 나지
-- 않습니다.
--
-- 플러터 쪽 호출부(lib/managers/supabase_manager.dart):
--   fetchUserEquipment(): select('id, data').eq('user_id', userId)
--   syncUserEquipment(items): upsert([{'id':..., 'user_id':..., 'data':...}], onConflict: 'id')
--                              + delete().eq('user_id', userId).not('id','in', currentIds)
-- 컬럼명/타입이 위 세 가지(id, user_id, data)와 정확히 일치해야
-- PostgREST가 요청을 그대로 받아들입니다 — "PostgrestException(... code: 400)"은
-- 보통 이 셋 중 하나가 없거나 타입이 안 맞을 때 나는 에러입니다.

create table if not exists user_equipment (
  id text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  data jsonb not null
);

alter table user_equipment enable row level security;

-- 재실행해도 안전하도록 기존 정책을 먼저 지우고 다시 만든다.
drop policy if exists "user_equipment_select_own" on user_equipment;
drop policy if exists "user_equipment_upsert_own" on user_equipment;
drop policy if exists "user_equipment_update_own" on user_equipment;
drop policy if exists "user_equipment_delete_own" on user_equipment;

-- 본인 행만 조회/수정 가능 — syncUserEquipment가 upsert/delete를 모두
-- 클라이언트에서 직접 호출하므로(별도 RPC 없음), insert/update/delete
-- 정책이 전부 필요하다.
create policy "user_equipment_select_own" on user_equipment
  for select using (auth.uid() = user_id);
create policy "user_equipment_upsert_own" on user_equipment
  for insert with check (auth.uid() = user_id);
create policy "user_equipment_update_own" on user_equipment
  for update using (auth.uid() = user_id);
create policy "user_equipment_delete_own" on user_equipment
  for delete using (auth.uid() = user_id);
