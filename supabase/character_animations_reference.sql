-- character_animations 테이블 — 캐릭터별 run/attack/wait 스프라이트 시트
-- 메타데이터를 코드가 아니라 DB에 두기 위한 테이블. 새 캐릭터를 추가하거나
-- 기존 캐릭터의 시트를 교체할 때 이 테이블에 행만 추가/수정하면 되고,
-- Flutter 코드에는 어떤 캐릭터가 몇 프레임인지 전혀 하드코딩돼 있지 않다
-- (lib/managers/character_animation_manager.dart 참고).
--
-- [주의: state 값은 'idle'이 아니라 'wait'다] 이 파일 초판에는 대기 모션의
-- state를 'idle'로 뒀었다 — 하지만 이 게임의 다른 모든 코드(AppImages의
-- playerActionFrame/playerActionAnimation 등, "player_n1_wait1.png" 같은
-- 실제 파일명 규칙)는 전부 'wait'를 쓴다. 두 이름이 어긋나면서 대기 모션
-- 조회만 항상 빗나가 레거시 PNG 프레임으로 폴백되는 버그가 있었다 —
-- 이제 코드('wait')와 스키마(아래 CHECK 제약)를 'wait'로 통일했다. 이미
-- 이 테이블을 'idle' 제약으로 먼저 만들어 뒀다면, 아래 CREATE TABLE은
-- `if not exists`라 기존 제약을 건드리지 않으므로 바로 아래 마이그레이션
-- 구간을 반드시 같이 실행해야 한다.
--
-- 플러터 쪽 호출부:
--   CharacterAnimationManager.instance.fetchSpec(characterId):
--     select('state, sheet_path, frame_count, frame_width, frame_height, step_time')
--       .eq('character_id', 내부적으로 변환된 마스터 ID)
-- 컬럼명/타입이 아래와 정확히 일치해야 합니다.
--
-- [주의: character_id는 장비/에셋 ID(gradeBadgeLabel, "N1")가 아니라
-- characters 마스터 테이블의 실제 character_id("char_n1")다] 이 게임
-- 코드 대부분(장비/에셋 경로 등)은 캐릭터를 "N1" 형식(Equipment
-- .gradeBadgeLabel)으로 가리키지만, 이 테이블은 characters 마스터
-- 테이블의 실제 PK 값과 같은 규칙("char_" 접두어 + 소문자, 예: "N1" →
-- "char_n1")을 그대로 외래키처럼 쓴다. Flutter 쪽
-- CharacterAnimationManager가 이 변환을 자동으로 해 주므로(
-- gradeBadgeLabel 그대로 fetchSpec에 넘기면 됨), 이 테이블에 행을 넣을
-- 때는 항상 "char_n1"처럼 마스터 테이블 규칙의 값을 써야 한다 — "N1"로
-- 넣으면 조회가 항상 0행으로 빗나간다.
--
-- sheet_path는 R2 objectKey입니다(예: assets/images/player/N/N1/
-- player_n1_run_sheet.png) — 공개 URL이 아니라, RemoteSpriteLoader가
-- StorageManager를 통해 매 요청마다 프리사인드 URL로 변환합니다. 이
-- 테이블 자체는 게임 콘텐츠 메타데이터(개인정보 아님)라 인증 없이도
-- 읽을 수 있도록 SELECT를 전체 공개합니다 — 쓰기는 Supabase 대시보드/
-- service_role에서만 하고, 클라이언트에는 insert/update/delete 정책을
-- 주지 않습니다.

create table if not exists character_animations (
  character_id text not null,
  state text not null check (state in ('run', 'attack', 'wait')),
  sheet_path text not null,
  frame_count integer not null check (frame_count > 0),
  frame_width integer not null check (frame_width > 0),
  frame_height integer not null check (frame_height > 0),
  step_time double precision not null check (step_time > 0),
  primary key (character_id, state)
);

-- 마이그레이션: 이 테이블이 이전 버전(state CHECK 제약이 'idle'을 허용)
-- 으로 이미 만들어져 있었다면, 위 CREATE TABLE은 `if not exists`라
-- 아무 효과가 없다 — 기존 제약/데이터를 명시적으로 바꿔야 한다. 재실행해도
-- 안전하다(제약이 없으면 drop이, 대상 행이 없으면 update가 조용히 아무
-- 일도 안 함). 순서가 중요하다 — 제약을 먼저 새로 걸면 기존 'idle' 행이
-- 그 시점에 이미 위반이라 ALTER 자체가 실패하므로, 반드시 (1) 옛 제약
-- 제거 → (2) 'idle' 행을 'wait'로 정리 → (3) 새 제약 추가 순서로 한다.
alter table character_animations drop constraint if exists character_animations_state_check;
update character_animations set state = 'wait' where state = 'idle';
alter table character_animations add constraint character_animations_state_check
  check (state in ('run', 'attack', 'wait'));

alter table character_animations enable row level security;

drop policy if exists "character_animations_select_all" on character_animations;

-- 로그인 여부와 무관하게 누구나 읽을 수 있다 — 게임 진행에 필요한
-- 공용 콘텐츠 메타데이터이지 유저별 데이터가 아니다.
create policy "character_animations_select_all" on character_animations
  for select using (true);

-- 예시 행(실제 시트 아트가 준비되면 이런 식으로 채운다) — character_id는
-- "N1"이 아니라 characters 마스터 테이블의 실제 값인 "char_n1":
-- insert into character_animations
--   (character_id, state, sheet_path, frame_count, frame_width, frame_height, step_time)
-- values
--   ('char_n1', 'run', 'assets/images/player/N/N1/player_n1_run_sheet.png', 3, 800, 720, 0.1),
--   ('char_n1', 'attack', 'assets/images/player/N/N1/player_n1_attack_sheet.png', 33, 800, 720, 0.05),
--   ('char_n1', 'wait', 'assets/images/player/N/N1/player_n1_wait_sheet.png', 5, 800, 720, 0.15)
-- on conflict (character_id, state) do update set
--   sheet_path = excluded.sheet_path,
--   frame_count = excluded.frame_count,
--   frame_width = excluded.frame_width,
--   frame_height = excluded.frame_height,
--   step_time = excluded.step_time;

-- ── 실행 후 검증(선택) ────────────────────────────────────────────────
-- 앱이 여전히 레거시 PNG 프레임으로 폴백된다면, 아래 쿼리로 실제 저장된
-- character_id/state 값이 코드가 기대하는 값과 정확히 일치하는지 눈으로
-- 바로 확인할 수 있다:
--
--   select character_id, state, sheet_path from character_animations order by character_id, state;
--
-- character_id는 "char_n1"처럼 "char_" 접두어가, state는 'run'/'attack'/
-- 'wait' 셋 중 하나만 있어야 한다(특히 'idle'이 하나라도 남아있으면 안
-- 됨 — 위 마이그레이션 UPDATE가 이미 정리했어야 한다).
