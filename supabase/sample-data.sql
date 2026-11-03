-- =====================================================================
-- DỮ LIỆU MẪU: 20 người chơi, mỗi người đã chơi 1 lượt
-- Cách dùng: Supabase → SQL Editor → New query → dán toàn bộ file → Run.
--
-- - Mã người chơi mẫu có dạng 5a5a5a5a-0000-4000-8000-0000000000NN (NN = 01..20)
--   để phân biệt với người chơi thật và xóa riêng được.
-- - Điểm, số trạm đúng ngay, tổng lần sai được TÍNH TỪ wrong_tries; điểm dùng chính
--   hàm private.calc_points của trò chơi (tối đa 1000: mỗi trạm 250 / 175 / 100 / 25).
-- - Cần chạy schema.sql trước (để có hàm private.calc_points).
-- - Chạy lại nhiều lần vẫn an toàn: lượt chơi mẫu cũ bị xóa rồi tạo lại.
-- =====================================================================

delete from public.plays
where player_id::text like '5a5a5a5a-0000-4000-8000-%';

with sample (n, full_name, wrong_tries, duration_ms) as (
  values
    ( 1, 'Nguyễn Thị Lan',       '{0,0,0,0}'::int[],  38000),
    ( 2, 'Trần Văn Minh',        '{0,0,0,0}'::int[],  45000),
    ( 3, 'Lê Thị Hồng Nhung',    '{0,1,0,0}'::int[],  41000),
    ( 4, 'Phạm Quốc Bảo',        '{0,0,1,0}'::int[],  52000),
    ( 5, 'Hoàng Thị Mai',        '{1,0,0,0}'::int[],  60000),
    ( 6, 'Vũ Đức Thắng',         '{0,1,1,0}'::int[],  47000),
    ( 7, 'Đặng Thị Thu Hà',      '{0,0,0,2}'::int[],  55000),
    ( 8, 'Bùi Văn Hùng',         '{1,1,0,0}'::int[],  63000),
    ( 9, 'Đỗ Thị Ngọc Ánh',      '{0,1,1,1}'::int[],  58000),
    (10, 'Ngô Minh Tuấn',        '{2,0,1,0}'::int[],  70000),
    (11, 'Dương Thị Kim Oanh',   '{1,1,1,0}'::int[],  66000),
    (12, 'Lý Thanh Sơn',         '{0,2,2,0}'::int[],  72000),
    (13, 'Huỳnh Thị Bích Trâm',  '{1,1,1,1}'::int[],  75000),
    (14, 'Phan Văn Lộc',         '{3,0,0,1}'::int[],  69000),
    (15, 'Võ Thị Thanh Tâm',     '{2,1,1,0}'::int[],  80000),
    (16, 'Trương Công Danh',     '{2,2,0,1}'::int[],  85000),
    (17, 'Đinh Thị Phương',      '{1,2,1,1}'::int[],  90000),
    (18, 'Mai Xuân Trường',      '{3,1,2,0}'::int[],  95000),
    (19, 'Tô Thị Diệu Linh',     '{2,2,2,1}'::int[], 100000),
    (20, 'Hồ Văn Khánh',         '{3,3,1,2}'::int[], 110000)
),
rows as (
  select ('5a5a5a5a-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid as player_id,
         n, full_name, wrong_tries, duration_ms
  from sample
),
new_players as (
  insert into public.players (player_id, full_name)
  select player_id, full_name from rows
  on conflict (player_id) do update set full_name = excluded.full_name, updated_at = now()
  returning player_id
)
insert into public.plays (player_id, wrong_tries, points, first_try, wrong_total, duration_ms, created_at)
select r.player_id,
       r.wrong_tries,
       private.calc_points(r.wrong_tries),
       (select count(*) from unnest(r.wrong_tries) as t(w) where w = 0),
       (select sum(w) from unnest(r.wrong_tries) as t(w)),
       r.duration_ms,
       now() - (21 - r.n) * interval '1 minute'   -- giả lập mỗi người chơi cách nhau 1 phút
from rows r
join new_players np on np.player_id = r.player_id;

-- Xem kết quả ngay sau khi tạo
select rank as "Hạng", full_name as "Họ và tên", points as "Điểm",
       round(duration_ms / 1000.0) as "Thời gian (giây)"
from public.get_leaderboard()
order by rank;

-- ---------------------------------------------------------------------
-- XÓA DỮ LIỆU MẪU (khi không cần nữa) – chỉ xóa 20 người mẫu, giữ người chơi thật:
--   delete from public.players where player_id::text like '5a5a5a5a-0000-4000-8000-%';
-- (lượt chơi của họ trong bảng plays tự xóa theo, nhờ "on delete cascade")
-- ---------------------------------------------------------------------
