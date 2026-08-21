-- 1:1 아이템 거래 시스템 — 참고 SQL. 이 프로젝트의 다른 참고 SQL
-- (combat_power_ranking_reference.sql 등)과 같은 성격입니다: 정확한
-- 기존 정책/타입(auth.users.id의 실제 타입, RLS 원문)이 이 저장소에
-- 없어 가정한 부분이 있으니, 배포 전 직접 검토/조정해 주세요.
--
-- 배포 순서: 1) 아래 테이블/컬럼 생성 → 2) RLS 정책 설정 → 3) execute_trade
-- 함수 생성. 클라이언트 코드(SupabaseManager)는 이 스키마를 그대로
-- 가정하고 있습니다.

-- ── 1. 일반 장비 서버 동기화 (거래의 전제 조건) ────────────────────────
-- user_pets와 완전히 같은 shape — 펫이 아닌 나머지 장비 전체를 담는다.
-- 이 테이블이 게임 진행의 신뢰 소스는 아니다(로컬이 여전히 1차 소스) —
-- 오직 "지금 이 아이템을 누가 갖고 있는지"를 서버가 판단하기 위한 미러다.
create table if not exists user_equipment (
  id text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  data jsonb not null
);

alter table user_equipment enable row level security;

-- 본인 행만 조회 가능 — 거래 상대의 아이템 데이터는 trade_items 임베드
-- 조회를 통해서만 봐야 하므로, 여기서는 본인 것만 허용한다. 만약
-- "상대 소유 여부 재검증"을 execute_trade가 아니라 클라이언트가 직접
-- 조회해서 해야 한다면 이 정책을 완화해야 하지만, 이 설계에서는 그
-- 재검증을 전부 execute_trade(SECURITY DEFINER, RLS 우회) 안에서
-- 하므로 본인 전용으로 좁혀도 안전하다.
create policy "user_equipment_select_own" on user_equipment
  for select using (auth.uid() = user_id);
create policy "user_equipment_upsert_own" on user_equipment
  for insert with check (auth.uid() = user_id);
create policy "user_equipment_update_own" on user_equipment
  for update using (auth.uid() = user_id);
create policy "user_equipment_delete_own" on user_equipment
  for delete using (auth.uid() = user_id);

-- ── 2. 거래 허용 설정 ──────────────────────────────────────────────
alter table profiles add column if not exists allow_trade boolean not null default false;

-- ── 3. 하루 거래 횟수 ──────────────────────────────────────────────
create table if not exists trade_daily_count (
  user_id uuid not null references auth.users(id) on delete cascade,
  trade_date date not null,
  count integer not null default 0,
  primary key (user_id, trade_date)
);

alter table trade_daily_count enable row level security;
create policy "trade_daily_count_select_own" on trade_daily_count
  for select using (auth.uid() = user_id);
-- insert/update는 execute_trade(SECURITY DEFINER)만 수행하므로 별도
-- insert/update 정책을 열어주지 않는다(클라이언트가 직접 조작 못 하게).

-- ── 4. 거래 세션 ───────────────────────────────────────────────────
create table if not exists trades (
  id uuid primary key default gen_random_uuid(),
  user_a uuid not null references auth.users(id) on delete cascade,
  user_b uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'active', 'completed', 'cancelled')),
  locked_a boolean not null default false,
  locked_b boolean not null default false,
  created_at timestamptz not null default now()
);

alter table trades enable row level security;
create policy "trades_select_participant" on trades
  for select using (auth.uid() = user_a or auth.uid() = user_b);
create policy "trades_insert_as_requester" on trades
  for insert with check (auth.uid() = user_a);
-- 상태/잠금 갱신은 참가자 본인만, 그리고 상대가 완료/취소시킨 거래를
-- 다시 pending으로 되돌리는 것 같은 악용을 막기 위해 실제 운영에서는
-- 컬럼 단위 제약(예: status 전이 트리거)을 추가하는 것을 권장합니다.
create policy "trades_update_participant" on trades
  for update using (auth.uid() = user_a or auth.uid() = user_b);

-- ── 5. 거래창에 올라간 아이템 ──────────────────────────────────────
create table if not exists trade_items (
  id uuid primary key default gen_random_uuid(),
  trade_id uuid not null references trades(id) on delete cascade,
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  equipment_id text not null references user_equipment(id) on delete cascade
);

alter table trade_items enable row level security;
create policy "trade_items_select_participant" on trade_items
  for select using (
    exists (
      select 1 from trades t
      where t.id = trade_id and (t.user_a = auth.uid() or t.user_b = auth.uid())
    )
  );
create policy "trade_items_insert_own" on trade_items
  for insert with check (auth.uid() = owner_user_id);
create policy "trade_items_delete_own" on trade_items
  for delete using (auth.uid() = owner_user_id);

-- ── 6. 거래 확정 RPC (원자적 이전 + 이중 검증) ─────────────────────────
-- 요구사항: "부계정 어뷰징을 막기 위해 안전하게" — 실제 소유권 이전은
-- 오직 이 함수 안에서만 일어난다. 클라이언트(TradeManager.confirmTrade)
-- 는 이 함수를 호출만 할 뿐, 아이템을 직접 옮기지 않는다.
--
-- 이중 검증(요구사항):
--   1) trade_items에 담긴 각 아이템이 "지금도" 실제로 그 유저 소유인지
--      user_equipment.user_id를 다시 조회해 재확인 — 클라이언트가 이미
--      다른 곳에서 그 아이템을 처분했거나(예: 분해) owner가 아닌
--      아이템을 억지로 올렸을 가능성을 차단한다.
--   2) 최고 등급(ssr/sssr/ur) 아이템이 섞여 있지 않은지 재확인 —
--      클라이언트 UI가 이미 걸러주지만, 변조된 클라이언트가 직접
--      trade_items에 insert하는 경로를 대비한 서버 측 최종 방어선이다.
-- 위반이 하나라도 있으면 예외를 던져 트랜잭션 전체를 롤백한다(부분
-- 이전 없음).
create or replace function execute_trade(p_trade_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_trade record;
  v_today date := current_date;
begin
  -- 행 잠금 — 동시에 같은 거래를 확정하려는 두 요청이 있어도 한쪽만
  -- 먼저 처리되고, 두 번째는 아래 status 체크에서 막힌다.
  select * into v_trade from trades where id = p_trade_id for update;

  if v_trade.id is null then
    raise exception 'trade not found';
  end if;
  if v_trade.status <> 'active' or not v_trade.locked_a or not v_trade.locked_b then
    raise exception 'trade not ready';
  end if;

  -- 이중 검증 1 + 2: 소유권 + 등급.
  if exists (
    select 1
    from trade_items ti
    join user_equipment ue on ue.id = ti.equipment_id
    where ti.trade_id = p_trade_id
      and (
        ue.user_id <> ti.owner_user_id
        or (ue.data->>'grade') in ('ssr', 'sssr', 'ur')
      )
  ) then
    raise exception 'invalid item in trade';
  end if;

  -- 하루 거래 횟수 재검증(양쪽 다) — 클라이언트가 보여주는 카운트를
  -- 신뢰하지 않고 여기서 다시 확인한다.
  --
  -- [보안 감사 2026-08-21] 맨 위의 `select ... for update`는 trade_id
  -- 단위로만 잠근다 — 같은 유저가 서로 다른 상대와 동시에 진행 중인
  -- 거래 두 건(각자 다른 trade_id)을 몇 밀리초 차이로 함께 confirm하면,
  -- 둘 다 이 지점에서 "아직 2건"을 읽고 통과해 하루 한도(3건)를 넘길 수
  -- 있었다(고전적인 read-then-write TOCTOU). 먼저 행이 반드시 존재하게
  -- 만든 뒤 `for update`로 그 유저의 오늘 카운트 행 자체를 잠가서, 두
  -- 번째 트랜잭션은 첫 번째가 커밋할 때까지 여기서 대기했다가 갱신된
  -- 값을 보게 한다.
  insert into trade_daily_count (user_id, trade_date, count)
  values (v_trade.user_a, v_today, 0), (v_trade.user_b, v_today, 0)
  on conflict (user_id, trade_date) do nothing;

  if (
    select count from trade_daily_count
    where user_id = v_trade.user_a and trade_date = v_today
    for update
  ) >= 3 or (
    select count from trade_daily_count
    where user_id = v_trade.user_b and trade_date = v_today
    for update
  ) >= 3 then
    raise exception 'daily trade limit reached';
  end if;

  -- 실제 이전: 각 아이템의 소유자를 상대방으로 교체.
  update user_equipment ue
  set user_id = case
    when ti.owner_user_id = v_trade.user_a then v_trade.user_b
    else v_trade.user_a
  end
  from trade_items ti
  where ti.trade_id = p_trade_id and ue.id = ti.equipment_id;

  update trades set status = 'completed' where id = p_trade_id;

  -- 위에서 이미 행을 잠가 뒀으므로 여기서는 단순 증가만 하면 된다.
  update trade_daily_count set count = count + 1
  where user_id = v_trade.user_a and trade_date = v_today;
  update trade_daily_count set count = count + 1
  where user_id = v_trade.user_b and trade_date = v_today;
end;
$$;
