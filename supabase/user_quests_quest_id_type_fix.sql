-- 버그: "[SupabaseManager] 퀘스트 진행도 일괄 동기화 실패:
-- PostgrestException(message: invalid input syntax for type integer:
-- "weekly_kill_5000", code: 22P02)"
--
-- 원인: user_quests.quest_id 컬럼이 integer로 만들어져 있는데, 실제
-- 퀘스트 id는 quest_catalog.id(이미 text)와 똑같이 항상 문자열입니다
-- (lib/models/quest_model.dart의 Quest.id는 String, 예:
-- "weekly_kill_5000" — {action_type}_{target_count} 조합으로 만들어진
-- 사람이 읽을 수 있는 id입니다. 순수 정수 id가 아닙니다).
--
-- lib/managers/quest_manager.dart/lib/managers/supabase_manager.dart의
-- upsertUserQuestProgressBatch/deleteUserQuestsByIds는 둘 다 처음부터
-- quest_id를 문자열로 다루고 있었으므로(코드 쪽 버그 아님), 고칠 곳은
-- Dart JSON 페이로드가 아니라 이 컬럼의 타입입니다.
--
-- 아래는 quest_id → text로 바꾸는 마이그레이션입니다. 외래키 제약이
-- 걸려 있다면 컬럼 타입을 바꾸기 전에 먼저 지워야 하는데, 정확한 제약
-- 이름은 이 저장소에 남아있지 않아 실제 이름으로 바꿔서 실행해 주세요
-- (Supabase 대시보드의 Database > Tables > user_quests > 제약조건
-- 탭에서 확인 가능합니다. 보통 `user_quests_quest_id_fkey` 형태입니다).

-- 1) 외래키 제약이 있다면 먼저 삭제 (제약 이름을 실제 이름으로 바꿔주세요)
alter table user_quests drop constraint if exists user_quests_quest_id_fkey;

-- 2) 컬럼 타입을 text로 변경 — 기존에 들어있던 값(있다면)도 문자열로
-- 안전하게 변환합니다.
alter table user_quests alter column quest_id type text using quest_id::text;

-- 3) quest_catalog.id를 참조하는 외래키를 다시 건다 — quest_catalog.id가
-- 이미 text 타입이므로 이제 타입이 맞습니다. quest_catalog에 없는 id가
-- 이미 들어있으면 이 ADD CONSTRAINT가 실패할 수 있으니, 실패하면 그런
-- 잔여 행부터 정리한 뒤 다시 실행해 주세요.
alter table user_quests
  add constraint user_quests_quest_id_fkey
  foreign key (quest_id) references quest_catalog(id);
