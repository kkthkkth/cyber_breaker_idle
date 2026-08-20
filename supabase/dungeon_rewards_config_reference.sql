-- dungeon_rewards_config 참조 스키마
--
-- 앱 코드(lib/models/dungeon_reward_config_model.dart,
-- lib/managers/dungeon_reward_manager.dart, SupabaseManager.fetchDungeonRewardsConfig)가
-- 이 컬럼명/타입을 그대로 가정하고 파싱합니다. 이미 만들어 두신 테이블의
-- 실제 컬럼명이 아래와 다르면, 이 SQL을 실행하지 말고 대신 두 파일
-- (DungeonRewardConfigEntry.fromJson / SupabaseManager.fetchDungeonRewardsConfig)만
-- 실제 컬럼명에 맞게 고치면 됩니다.
--
-- 던전을 구분하는 dungeon_type 값은 앱 코드에서 문자열 상수로 씁니다:
--   'rune_labyrinth'          — 룬의 미궁 (요일 던전 목요일 슬롯)
--   'guild_victory_sanctuary' — 승리자의 성소 (길드전 승리 전용 길드 던전)
--
-- item_type 값: 'gold' | 'gem' | 'rune_fragment' | 'consumable' | 'equipment'
-- item_type이 'consumable'일 때만 item_name을 사용합니다(ConsumableType의
-- enum 이름 또는 한글 표시명과 대소문자/공백 무시하고 일치해야 합니다).

create table if not exists dungeon_rewards_config (
  id            text primary key,
  dungeon_type  text not null,
  item_type     text not null check (item_type in ('gold', 'gem', 'rune_fragment', 'consumable', 'equipment')),
  item_name     text,
  probability   numeric not null check (probability >= 0 and probability <= 1),
  min_quantity  integer not null check (min_quantity >= 0),
  max_quantity  integer not null check (max_quantity >= min_quantity)
);

-- 공개 읽기 전용 참조 데이터 — 다른 카탈로그 테이블(artifacts,
-- monster_drop_table 등)과 같은 RLS 정책 관례를 따릅니다.
alter table dungeon_rewards_config enable row level security;

create policy "dungeon_rewards_config is publicly readable"
  on dungeon_rewards_config for select
  using (true);

-- 예시 시드 — 클리어 1회마다 각 행을 독립적으로 굴려서, 당첨된 행마다
-- min_quantity~max_quantity 사이 무작위 수량을 지급합니다.
insert into dungeon_rewards_config (id, dungeon_type, item_type, item_name, probability, min_quantity, max_quantity)
values
  ('rune_labyrinth_fragment', 'rune_labyrinth', 'rune_fragment', null, 0.8, 5, 12),
  ('rune_labyrinth_gold', 'rune_labyrinth', 'gold', null, 0.3, 100, 300),
  ('victory_sanctuary_fragment', 'guild_victory_sanctuary', 'rune_fragment', null, 1.0, 15, 30),
  ('victory_sanctuary_gem', 'guild_victory_sanctuary', 'gem', null, 0.5, 10, 50)
on conflict (id) do nothing;
