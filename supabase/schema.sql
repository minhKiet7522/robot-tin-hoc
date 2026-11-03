-- =====================================================================
-- CSDL cho trò chơi "Nạp năng lượng cho Robot Tin học"
-- Cách dùng: Supabase → SQL Editor → New query → dán toàn bộ file → Run.
-- Chạy lại nhiều lần vẫn an toàn (không xóa dữ liệu đã có).
--
-- Người chơi chỉ nhập họ và tên. Mỗi trình duyệt tự sinh một mã ngẫu nhiên
-- (player_id, dạng UUID) lưu trong máy: cùng máy chơi lại thì thay kết quả cũ,
-- hai người trùng họ tên trên hai máy vẫn là hai dòng riêng.
--
-- Nguyên tắc bảo mật: trình duyệt KHÔNG đọc/ghi thẳng vào bảng (RLS bật,
-- không có policy). Mọi thao tác đi qua 3 hàm:
--   register_player – lưu họ tên khi bấm "Bắt đầu"
--   submit_score    – gửi một lượt chơi, máy chủ tự tính điểm và thứ hạng
--   get_leaderboard – bảng xếp hạng (không trả về player_id của ai cả)
-- =====================================================================

create schema if not exists private;   -- schema không được mở ra API

create table if not exists public.players (
  player_id  uuid primary key,
  full_name  text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.plays (
  id          bigint generated always as identity primary key,
  player_id   uuid not null references public.players (player_id) on delete cascade,
  wrong_tries int[] not null,   -- số lần chọn sai trước khi đúng, theo từng trạm
  points      int not null,
  first_try   int not null,     -- số trạm đúng ngay lần đầu
  wrong_total int not null,
  duration_ms int not null,
  created_at  timestamptz not null default now()
);
create index if not exists plays_player_idx on public.plays (player_id, created_at desc);

alter table public.players enable row level security;
alter table public.plays   enable row level security;
revoke all on public.players, public.plays from anon, authenticated;

-- Chuẩn hóa họ tên: bỏ khoảng trắng thừa; báo lỗi nếu quá ngắn / quá dài
create or replace function private.clean_name(p_full_name text)
returns text
language plpgsql
immutable
as $$
declare
  v_name text := regexp_replace(trim(coalesce(p_full_name, '')), '\s+', ' ', 'g');
begin
  if char_length(v_name) < 2 or char_length(v_name) > 80 then
    raise exception 'Họ tên không hợp lệ';
  end if;
  return v_name;
end
$$;

-- Xếp hạng theo lượt GẦN NHẤT của mỗi người chơi (chơi lại sẽ thay kết quả cũ, kể cả khi điểm thấp hơn):
-- điểm cao hơn trước, bằng điểm thì nhanh hơn trước
create or replace function private.ranked()
returns table (
  rank int, player_id uuid, full_name text, points int, first_try int,
  stations int, wrong_total int, duration_ms int, played_at timestamptz
)
language sql
stable
as $$
  with latest as (
    select distinct on (p.player_id)
           p.player_id, p.points, p.first_try, cardinality(p.wrong_tries) as stations,
           p.wrong_total, p.duration_ms, p.created_at
    from public.plays p
    order by p.player_id, p.created_at desc, p.id desc
  )
  select (rank() over (order by l.points desc, l.duration_ms asc))::int,
         l.player_id, pl.full_name, l.points, l.first_try, l.stations,
         l.wrong_total, l.duration_ms, l.created_at
  from latest l
  join public.players pl on pl.player_id = l.player_id
$$;

-- Lưu người chơi khi bấm "Bắt đầu" (trò chơi chờ hàm này thành công rồi mới vào trạm 1).
-- Upsert theo player_id nên bấm lại / nhiều người cùng lúc đều an toàn; trả về họ tên đã lưu.
create or replace function public.register_player(p_player_id uuid, p_full_name text)
returns table (full_name text)
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_name text := private.clean_name(p_full_name);
begin
  if p_player_id is null then
    raise exception 'Thiếu mã người chơi';
  end if;

  insert into public.players (player_id, full_name) values (p_player_id, v_name)
  on conflict (player_id) do update set full_name = excluded.full_name, updated_at = now();

  return query select v_name;
end
$$;

-- Điểm mỗi trạm: đúng ngay 100, sai 1 lần 70, sai 2 lần 40, sai 3 lần 10
create or replace function public.submit_score(
  p_player_id uuid,
  p_full_name text,
  p_wrong_tries int[],
  p_duration_ms int
)
returns table (points int, rank int, total_players int)
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_name   text := private.clean_name(p_full_name);
  v_n      int  := coalesce(cardinality(p_wrong_tries), 0);
  v_points int;
  v_first  int;
  v_wrong  int;
begin
  if p_player_id is null then
    raise exception 'Thiếu mã người chơi';
  end if;
  if v_n < 1 or v_n > 20
     or exists (select 1 from unnest(p_wrong_tries) as t(w) where w is null or w < 0 or w > 3) then
    raise exception 'Dữ liệu lượt chơi không hợp lệ';
  end if;
  if p_duration_ms is null or p_duration_ms < 2000 or p_duration_ms > 3600000 then
    raise exception 'Thời gian chơi không hợp lệ';
  end if;
  if exists (select 1 from public.plays p
             where p.player_id = p_player_id and p.created_at > now() - interval '5 seconds') then
    raise exception 'Gửi quá nhanh, vui lòng thử lại sau vài giây';
  end if;

  select sum(greatest(100 - 30 * w, 10)), count(*) filter (where w = 0), sum(w)
    into v_points, v_first, v_wrong
  from unnest(p_wrong_tries) as t(w);

  insert into public.players (player_id, full_name) values (p_player_id, v_name)
  on conflict (player_id) do update set full_name = excluded.full_name, updated_at = now();

  insert into public.plays (player_id, wrong_tries, points, first_try, wrong_total, duration_ms)
  values (p_player_id, p_wrong_tries, v_points, v_first, v_wrong, p_duration_ms);

  return query
    select v_points, r.rank, (select count(distinct p.player_id)::int from public.plays p)
    from private.ranked() r
    where r.player_id = p_player_id;
end
$$;

-- p_player_id (tùy chọn): mã của người đang xem, để đánh dấu dòng của chính họ (is_me)
create or replace function public.get_leaderboard(p_player_id uuid default null, p_limit int default 200)
returns table (
  rank int, full_name text, points int, first_try int,
  stations int, wrong_total int, duration_ms int, is_me boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select r.rank, r.full_name, r.points, r.first_try, r.stations,
         r.wrong_total, r.duration_ms, coalesce(r.player_id = p_player_id, false)
  from private.ranked() r
  order by r.rank, r.played_at
  limit least(greatest(coalesce(p_limit, 200), 1), 500)
$$;

revoke all on function private.clean_name(text) from public;
revoke all on function private.ranked() from public;
revoke all on function public.register_player(uuid, text) from public;
revoke all on function public.submit_score(uuid, text, int[], int) from public;
revoke all on function public.get_leaderboard(uuid, int) from public;
grant execute on function public.register_player(uuid, text) to anon, authenticated;
grant execute on function public.submit_score(uuid, text, int[], int) to anon, authenticated;
grant execute on function public.get_leaderboard(uuid, int) to anon, authenticated;
