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
-- Các hàm quản trị admin_* (cuối file) chỉ Edge Function "admin" gọi được.
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

-- Điểm một lượt chơi – nguồn DUY NHẤT của công thức tính điểm. Tổng tối đa luôn là 1000.
-- Mỗi trạm nhận 1000/N điểm nhân hệ số theo số lần sai w trước khi chọn đúng:
--   w = 0 → 100%, w = 1 → 70%, w = 2 → 40%, w = 3 → 10%
-- Với 4 trạm: 250 / 175 / 100 / 25 điểm mỗi trạm.
create or replace function private.calc_points(p_wrong_tries int[])
returns int
language sql
immutable
as $$
  select round(sum(greatest(10 - 3 * w, 1)) * 100.0 / cardinality(p_wrong_tries))::int
  from unnest(p_wrong_tries) as t(w)
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

-- Gửi một lượt chơi; điểm tính bằng private.calc_points (tối đa 1000)
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

  v_points := private.calc_points(p_wrong_tries);
  select count(*) filter (where w = 0), sum(w)
    into v_first, v_wrong
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
revoke all on function private.calc_points(int[]) from public;
revoke all on function private.ranked() from public;
revoke all on function public.register_player(uuid, text) from public;
revoke all on function public.submit_score(uuid, text, int[], int) from public;
revoke all on function public.get_leaderboard(uuid, int) from public;
grant execute on function public.register_player(uuid, text) to anon, authenticated;
grant execute on function public.submit_score(uuid, text, int[], int) to anon, authenticated;
grant execute on function public.get_leaderboard(uuid, int) to anon, authenticated;

-- Quy đổi các lượt chơi đã có sang công thức điểm hiện tại (vd thang 400 cũ → 1000).
-- Chạy lại an toàn: chỉ cập nhật lượt nào có điểm khác với công thức.
update public.plays
set points = private.calc_points(wrong_tries)
where points is distinct from private.calc_points(wrong_tries);

-- =====================================================================
-- QUẢN TRỊ: trang admin.html (đăng nhập bằng tên đăng nhập + mật khẩu)
-- Xem, sửa họ tên, xóa từng người chơi hoặc xóa VĨNH VIỄN toàn bộ người chơi.
--
-- Các hàm admin_* CHỈ cấp quyền cho service_role: trình duyệt KHÔNG gọi thẳng
-- được, mà phải đi qua Edge Function "admin" (supabase/functions/admin), nơi giữ
-- khóa bí mật của máy chủ.
--
-- Mật khẩu chỉ lưu dạng băm bcrypt. Đăng nhập thành công nhận một phiên 8 giờ
-- (CSDL chỉ lưu mã băm SHA-256 của phiên). Sai 5 lần liên tiếp trong 10 phút
-- thì tạm khóa đăng nhập 10 phút.
--
-- Đặt / đổi tài khoản (giáo viên tự chạy trong SQL Editor; mật khẩu ít nhất 8 ký tự):
--   select private.set_admin_account('ten-dang-nhap', 'mật-khẩu-của-bạn');
-- Chạy lại lệnh này để đổi mật khẩu: mọi nơi đang đăng nhập bị đăng xuất, và mở khóa luôn.
-- =====================================================================

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

create table if not exists private.admin_config (
  id            int primary key default 1 check (id = 1),   -- chỉ một tài khoản quản trị
  password_hash text not null,
  updated_at    timestamptz not null default now()
);
alter table private.admin_config add column if not exists username text;

create table if not exists private.admin_attempts (
  id         bigint generated always as identity primary key,
  success    boolean not null,
  created_at timestamptz not null default now()
);

create table if not exists private.admin_sessions (
  token_hash text primary key,   -- SHA-256 của mã phiên; mã gốc chỉ nằm ở trình duyệt admin
  created_at timestamptz not null default now(),
  expires_at timestamptz not null
);

-- Bản trước: nút "Xóa bảng xếp hạng" ở link #quan-tri chỉ cần mật khẩu. Nay thay bằng admin.html.
drop function if exists public.reset_leaderboard(text);
drop function if exists private.set_admin_password(text);
drop table if exists private.archived_plays;
drop sequence if exists private.archive_seq;

create or replace function private.set_admin_account(p_username text, p_password text)
returns text
language plpgsql
as $$
declare
  v_user text := lower(trim(coalesce(p_username, '')));
begin
  if v_user !~ '^[a-z0-9._-]{3,32}$' then
    raise exception 'Tên đăng nhập cần 3–32 ký tự: chữ không dấu, số, dấu chấm, gạch ngang hoặc gạch dưới';
  end if;
  if char_length(coalesce(p_password, '')) < 8 then
    raise exception 'Mật khẩu quản trị cần ít nhất 8 ký tự';
  end if;
  insert into private.admin_config (id, username, password_hash)
  values (1, v_user, extensions.crypt(p_password, extensions.gen_salt('bf', 10)))
  on conflict (id) do update
    set username = excluded.username, password_hash = excluded.password_hash, updated_at = now();
  delete from private.admin_attempts where true;   -- mở khóa đăng nhập
  delete from private.admin_sessions where true;   -- đăng xuất mọi nơi
  return 'Đã đặt tài khoản quản trị: ' || v_user;
end
$$;

-- Báo lỗi 401 (PostgREST đổi SQLSTATE PT401 thành HTTP 401) nếu phiên sai hoặc đã hết hạn
create or replace function private.admin_check(p_token text)
returns void
language plpgsql
stable
as $$
begin
  if p_token is null or not exists (
    select 1 from private.admin_sessions s
    where s.token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex')
      and s.expires_at > now()
  ) then
    raise exception using errcode = 'PT401', message = 'Phiên đăng nhập đã hết hạn, vui lòng đăng nhập lại';
  end if;
end
$$;

-- Sai tài khoản/mật khẩu thì TRẢ VỀ ok = false (không raise) để lần thử sai được ghi lại
create or replace function public.admin_login(p_username text, p_password text)
returns table (ok boolean, message text, token text, expires_at timestamptz)
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_user  text;
  v_hash  text;
  v_fails int;
  v_now   timestamptz := now();
  v_match boolean;
  v_token text;
  v_exp   timestamptz;
begin
  select c.username, c.password_hash into v_user, v_hash from private.admin_config c where c.id = 1;
  if v_user is null then
    return query select false, 'Chưa thiết lập tài khoản quản trị (xem README).', null::text, null::timestamptz;
    return;
  end if;

  select count(*) into v_fails
  from private.admin_attempts a
  where not a.success
    and a.created_at > v_now - interval '10 minutes'
    and a.created_at > coalesce((select max(b.created_at) from private.admin_attempts b where b.success), '-infinity');
  if v_fails >= 5 then
    return query select false, 'Nhập sai quá nhiều lần. Vui lòng thử lại sau 10 phút.', null::text, null::timestamptz;
    return;
  end if;

  -- Luôn băm mật khẩu (kể cả khi sai tên) để thời gian trả lời không lộ tên đăng nhập đúng
  v_match := extensions.crypt(coalesce(p_password, ''), v_hash) = v_hash;
  if not v_match or lower(trim(coalesce(p_username, ''))) <> v_user then
    insert into private.admin_attempts (success) values (false);
    return query select false, 'Sai tên đăng nhập hoặc mật khẩu.', null::text, null::timestamptz;
    return;
  end if;

  insert into private.admin_attempts (success) values (true);
  delete from private.admin_attempts a where a.created_at < v_now - interval '1 day';
  delete from private.admin_sessions s where s.expires_at < v_now;

  v_token := encode(extensions.gen_random_bytes(32), 'hex');
  v_exp   := v_now + interval '8 hours';
  insert into private.admin_sessions (token_hash, expires_at)
  values (encode(extensions.digest(v_token, 'sha256'), 'hex'), v_exp);

  return query select true, 'Đăng nhập thành công', v_token, v_exp;
end
$$;

create or replace function public.admin_logout(p_token text)
returns void
language sql
security definer
set search_path = ''
as $$
  delete from private.admin_sessions s
  where s.token_hash = encode(extensions.digest(coalesce(p_token, ''), 'sha256'), 'hex')
$$;

-- Toàn bộ người chơi, kể cả người đã đăng ký nhưng chưa chơi xong (rank/points = null)
create or replace function public.admin_list_players(p_token text)
returns table (
  player_id uuid, full_name text, created_at timestamptz, updated_at timestamptz,
  plays int, rank int, points int, duration_ms int, last_played timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  perform private.admin_check(p_token);
  return query
    select p.player_id, p.full_name, p.created_at, p.updated_at,
           (select count(*)::int from public.plays x where x.player_id = p.player_id),
           r.rank, r.points, r.duration_ms, r.played_at
    from public.players p
    left join private.ranked() r on r.player_id = p.player_id
    order by r.rank nulls last, r.played_at, p.created_at desc;
end
$$;

create or replace function public.admin_update_player(p_token text, p_player_id uuid, p_full_name text)
returns table (player_id uuid, full_name text)
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_name text;
begin
  perform private.admin_check(p_token);
  v_name := private.clean_name(p_full_name);
  update public.players p set full_name = v_name, updated_at = now() where p.player_id = p_player_id;
  if not found then
    raise exception using errcode = 'PT404', message = 'Không tìm thấy người chơi (có thể đã bị xóa)';
  end if;
  return query select p_player_id, v_name;
end
$$;

-- Xóa một người chơi; các lượt chơi của họ tự xóa theo (on delete cascade)
create or replace function public.admin_delete_player(p_token text, p_player_id uuid)
returns table (full_name text)
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_name text;
begin
  perform private.admin_check(p_token);
  delete from public.players p where p.player_id = p_player_id returning p.full_name into v_name;
  if not found then
    raise exception using errcode = 'PT404', message = 'Không tìm thấy người chơi (có thể đã bị xóa)';
  end if;
  return query select v_name;
end
$$;

-- Xóa VĨNH VIỄN toàn bộ người chơi + lượt chơi (không lưu trữ, không khôi phục được)
create or replace function public.admin_delete_all(p_token text)
returns table (deleted int)
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_count int;
begin
  perform private.admin_check(p_token);
  -- Khóa theo đúng thứ tự submit_score ghi (players rồi plays) để không deadlock,
  -- và để lượt gửi đúng lúc này chờ xong rồi mới ghi vào bảng mới
  lock table public.players, public.plays in exclusive mode;
  select count(*) into v_count from public.players;
  -- "where true" là bắt buộc: Supabase bật pg_safeupdate, chặn DELETE không có WHERE khi gọi qua API
  delete from public.players where true;
  return query select v_count;
end
$$;

revoke all on function private.set_admin_account(text, text) from public;
revoke all on function private.admin_check(text) from public;
-- Supabase tự cấp quyền chạy hàm mới cho anon/authenticated: phải thu hồi rõ ràng
revoke all on function public.admin_login(text, text)               from public, anon, authenticated;
revoke all on function public.admin_logout(text)                    from public, anon, authenticated;
revoke all on function public.admin_list_players(text)              from public, anon, authenticated;
revoke all on function public.admin_update_player(text, uuid, text) from public, anon, authenticated;
revoke all on function public.admin_delete_player(text, uuid)       from public, anon, authenticated;
revoke all on function public.admin_delete_all(text)                from public, anon, authenticated;
grant execute on function public.admin_login(text, text)               to service_role;
grant execute on function public.admin_logout(text)                    to service_role;
grant execute on function public.admin_list_players(text)              to service_role;
grant execute on function public.admin_update_player(text, uuid, text) to service_role;
grant execute on function public.admin_delete_player(text, uuid)       to service_role;
grant execute on function public.admin_delete_all(text)                to service_role;
