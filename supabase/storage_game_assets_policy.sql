-- game-assets 버킷: 게임 이미지(플레이어/펫/스킬/배경/스토리 등, [AppImages]/
-- [AssetPaths] 참고)를 담는 Supabase Storage 버킷. RemoteSpriteLoader/
-- CustomSafeImage가 https://<project-ref>.supabase.co/storage/v1/object/public/
-- game-assets/... 형태의 공개 URL로 직접 내려받으므로, 이 버킷은 "Public"
-- 버킷이어야 하고 storage.objects에 누구나(anon 포함) 읽을 수 있는 RLS
-- SELECT 정책도 있어야 한다 — 둘 중 하나라도 빠지면 이미지가 전부 404/400으로
-- 깨진다.
--
-- Supabase 대시보드 SQL Editor에서 그대로 실행하면 된다. 여러 번 실행해도
-- 안전하도록(idempotent) 작성했다 — 버킷/정책이 이미 있으면 조용히 건너뛰거나
-- 덮어쓴다.

-- 1) 버킷이 없으면 생성하고, 있으면 public 플래그만 강제로 켠다.
--    (public=false인 상태로 이미 존재하면 /object/public/ 경로 자체가
--    항상 400을 반환하므로, 여기서 반드시 true로 맞춰 둔다.)
insert into storage.buckets (id, name, public)
values ('game-assets', 'game-assets', true)
on conflict (id) do update set public = true;

-- 2) storage.objects는 Supabase 프로젝트에서 기본적으로 RLS가 켜져 있지만,
--    혹시 꺼져 있는 환경을 위해 명시적으로 한 번 더 켠다(이미 켜져 있어도
--    에러 없이 무시된다).
alter table storage.objects enable row level security;

-- 3) game-assets 버킷 안의 모든 파일에 대해 "누구나"(anon + authenticated)
--    SELECT(읽기)할 수 있는 정책. 같은 이름의 정책이 이미 있으면 먼저 지우고
--    다시 만든다 — CREATE POLICY는 이름 중복을 허용하지 않는다.
drop policy if exists "game-assets public read" on storage.objects;

create policy "game-assets public read"
on storage.objects
for select
to public
using (bucket_id = 'game-assets');

-- [주의] 이 정책은 "읽기(SELECT)"만 연다 — 업로드(INSERT)/수정(UPDATE)/
-- 삭제(DELETE)는 여전히 막혀 있다(정책이 없으면 기본 거부). 클라이언트 앱은
-- 이미지를 읽기만 하므로 이걸로 충분하고, 실제 에셋 업로드는 서비스 롤 키나
-- Supabase 대시보드에서 관리자가 직접 수행해야 한다.
