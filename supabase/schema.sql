-- =====================================================================
-- CSDL cho trò chơi "Nạp năng lượng cho Robot Tin học"
-- Cách dùng: Supabase → SQL Editor → New query → dán toàn bộ file → Run.
-- Chạy lại nhiều lần vẫn an toàn (không xóa dữ liệu đã có).
--
-- Nguyên tắc bảo mật: trình duyệt KHÔNG đọc/ghi thẳng vào bảng (RLS bật,
-- không có policy). Mọi thao tác đi qua 2 hàm:
--   submit_score    – gửi một lượt chơi, máy chủ tự tính điểm và thứ hạng
--   get_leaderboard – bảng xếp hạng, email đã được che (vd: ng***@gmail.com)
-- =====================================================================

create schema if not exists private;   -- schema không được mở ra API

create table if not exists public.players (
  email      text primary key,
  full_name  text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.plays (
  id          bigint generated always as identity primary key,
  email       text not null references public.players (email) on delete cascade,
  wrong_tries int[] not null,   -- số lần chọn sai trước khi đúng, theo từng trạm
  points      int not null,
  first_try   int not null,     -- số trạm đúng ngay lần đầu
  wrong_total int not null,
  duration_ms int not null,
  created_at  timestamptz not null default now()
);
create index if not exists plays_email_idx on public.plays (email, created_at desc);

alter table public.players enable row level security;
alter table public.plays   enable row level security;
revoke all on public.players, public.plays from anon, authenticated;

-- Che email: giữ 2 ký tự đầu (1 ký tự nếu phần trước @ quá ngắn) + tên miền
create or replace function private.mask_email(p_email text)
returns text
language sql
immutable
as $$
  select case
    when position('@' in p_email) <= 3
      then left(p_email, 1) || '***' || substr(p_email, position('@' in p_email))
    else left(p_email, 2) || '***' || substr(p_email, position('@' in p_email))
  end
$$;

-- Xếp hạng theo lượt TỐT NHẤT của mỗi email: điểm cao hơn trước, bằng điểm thì nhanh hơn trước
create or replace function private.ranked()
returns table (
  rank int, email text, full_name text, points int, first_try int,
  stations int, wrong_total int, duration_ms int, played_at timestamptz
)
language sql
stable
as $$
  with best as (
    select distinct on (p.email)
           p.email, p.points, p.first_try, cardinality(p.wrong_tries) as stations,
           p.wrong_total, p.duration_ms, p.created_at
    from public.plays p
    order by p.email, p.points desc, p.duration_ms asc, p.created_at asc
  )
  select (rank() over (order by b.points desc, b.duration_ms asc))::int,
         b.email, pl.full_name, b.points, b.first_try, b.stations,
         b.wrong_total, b.duration_ms, b.created_at
  from best b
  join public.players pl on pl.email = b.email
$$;

-- Điểm mỗi trạm: đúng ngay 100, sai 1 lần 70, sai 2 lần 40, sai 3 lần 10
create or replace function public.submit_score(
  p_email text,
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
  v_email  text := lower(trim(coalesce(p_email, '')));
  v_name   text := regexp_replace(trim(coalesce(p_full_name, '')), '\s+', ' ', 'g');
  v_n      int  := coalesce(cardinality(p_wrong_tries), 0);
  v_points int;
  v_first  int;
  v_wrong  int;
begin
  if length(v_email) > 254 or v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'Email không hợp lệ';
  end if;
  if char_length(v_name) < 2 or char_length(v_name) > 80 then
    raise exception 'Họ tên không hợp lệ';
  end if;
  if v_n < 1 or v_n > 20
     or exists (select 1 from unnest(p_wrong_tries) as t(w) where w is null or w < 0 or w > 3) then
    raise exception 'Dữ liệu lượt chơi không hợp lệ';
  end if;
  if p_duration_ms is null or p_duration_ms < 2000 or p_duration_ms > 3600000 then
    raise exception 'Thời gian chơi không hợp lệ';
  end if;
  if exists (select 1 from public.plays p
             where p.email = v_email and p.created_at > now() - interval '5 seconds') then
    raise exception 'Gửi quá nhanh, vui lòng thử lại sau vài giây';
  end if;

  select sum(greatest(100 - 30 * w, 10)), count(*) filter (where w = 0), sum(w)
    into v_points, v_first, v_wrong
  from unnest(p_wrong_tries) as t(w);

  insert into public.players (email, full_name) values (v_email, v_name)
  on conflict (email) do update set full_name = excluded.full_name, updated_at = now();

  insert into public.plays (email, wrong_tries, points, first_try, wrong_total, duration_ms)
  values (v_email, p_wrong_tries, v_points, v_first, v_wrong, p_duration_ms);

  return query
    select v_points, r.rank, (select count(*)::int from public.players)
    from private.ranked() r
    where r.email = v_email;
end
$$;

create or replace function public.get_leaderboard(p_limit int default 200)
returns table (
  rank int, full_name text, email_masked text, points int,
  first_try int, stations int, wrong_total int, duration_ms int
)
language sql
stable
security definer
set search_path = ''
as $$
  select r.rank, r.full_name, private.mask_email(r.email), r.points,
         r.first_try, r.stations, r.wrong_total, r.duration_ms
  from private.ranked() r
  order by r.rank, r.played_at
  limit least(greatest(coalesce(p_limit, 200), 1), 500)
$$;

revoke all on function private.mask_email(text) from public;
revoke all on function private.ranked() from public;
revoke all on function public.submit_score(text, text, int[], int) from public;
revoke all on function public.get_leaderboard(int) from public;
grant execute on function public.submit_score(text, text, int[], int) to anon, authenticated;
grant execute on function public.get_leaderboard(int) to anon, authenticated;
