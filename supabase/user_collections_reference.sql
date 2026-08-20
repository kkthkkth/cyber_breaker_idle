-- user_collections 테이블 — 컬렉션(도감 세트) 완성 기록 동기화가
-- 정확히 이 스키마를 가정합니다(lib/managers/supabase_manager.dart의
-- fetchUserCollections/syncCollectionCompletion).
--
-- 이미 user_collections 테이블을 만들어 두셨다면, 아래 컬럼명(user_id,
-- collection_id)과 정확히 일치하는지만 확인해 주세요 — 다르면 이 SQL을
-- 실행하지 말고 대신 lib/managers/supabase_manager.dart의 두 메서드만
-- 실제 컬럼명에 맞게 고치면 됩니다.
--
-- 플러터 쪽 호출부:
--   fetchUserCollections(): select('collection_id').eq('user_id', userId)
--   syncCollectionCompletion(id): upsert({'user_id':..., 'collection_id':...},
--                                          onConflict: 'user_id, collection_id')
-- 컬렉션 정의 자체(master_collections)와는 다른 테이블입니다 — 이 테이블은
-- "이 유저가 어떤 컬렉션 id를 완성했는지"만 기록하는 진행 기록용입니다.

create table if not exists user_collections (
  user_id uuid not null references auth.users(id) on delete cascade,
  collection_id text not null,
  completed_at timestamptz not null default now(),
  primary key (user_id, collection_id)
);

alter table user_collections enable row level security;

drop policy if exists "user_collections_select_own" on user_collections;
drop policy if exists "user_collections_upsert_own" on user_collections;

-- 본인 완성 기록만 조회/등록 가능 — 완성은 영구적이라(재획득/삭제 개념
-- 없음) update/delete 정책은 열어주지 않는다.
create policy "user_collections_select_own" on user_collections
  for select using (auth.uid() = user_id);
create policy "user_collections_upsert_own" on user_collections
  for insert with check (auth.uid() = user_id);
