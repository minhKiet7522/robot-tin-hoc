-- =====================================================================
-- CHUYỂN ĐỔI MỘT LẦN: bỏ email, nhận diện người chơi theo thiết bị (player_id)
-- ⚠️ XÓA TOÀN BỘ dữ liệu người chơi và lượt chơi hiện có.
--
-- Thứ tự thực hiện trong Supabase → SQL Editor:
--   1. Chạy file này
--   2. Chạy toàn bộ file schema.sql
-- =====================================================================

drop function if exists public.register_player(text, text);
drop function if exists public.submit_score(text, text, int[], int);
drop function if exists public.get_leaderboard(int);
drop function if exists private.ranked();
drop function if exists private.mask_email(text);
drop table if exists public.plays, public.players;
