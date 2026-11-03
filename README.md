# Nạp Năng Lượng Cho Robot Tin Học – Cyber Robot Adventure

Trò chơi trắc nghiệm 4 trạm dành cho tiết Chuyên đề Tin học. Người tham gia mở link, chỉ cần nhập **họ và tên** rồi chơi. Chơi xong, kết quả được lưu và hiện trên **bảng xếp hạng**.

- Giao diện: một trang web tĩnh, chạy miễn phí trên **GitHub Pages**
- Lưu điểm và xếp hạng: **Supabase** gói miễn phí
- Chi phí: **0đ**. Không cần mua tên miền hay hosting.

## Cấu trúc thư mục

| File | Vai trò |
|---|---|
| `index.html` | Toàn bộ trò chơi: giao diện, câu hỏi, đăng nhập, bảng xếp hạng |
| `config.js` | Địa chỉ và khóa công khai của Supabase (bạn tự điền) |
| `supabase/schema.sql` | Tạo bảng và hàm trên Supabase (chạy một lần) |
| `supabase/migrate-bo-email.sql` | Chỉ dùng một lần khi chuyển từ bản cũ có email (xóa bảng cũ) |

## Cách tính điểm và xếp hạng

- Mỗi trạm: đúng ngay lần đầu được **100**, sai 1 lần được **70**, sai 2 lần được **40**, sai 3 lần được **10**. Tối đa **400 điểm**.
- Máy chủ tự tính điểm. Mỗi người chơi chỉ tính **lượt chơi gần nhất**: chơi lại thì kết quả mới thay kết quả cũ, kể cả khi điểm thấp hơn. Ai nhiều điểm hơn đứng trên; bằng điểm thì ai hoàn thành **nhanh hơn** đứng trên.
- **Nhận diện người chơi theo thiết bị:** mỗi trình duyệt tự sinh một mã ngẫu nhiên, lưu trong máy.
  - Cùng máy chơi lại thì chỉ chiếm một dòng trên bảng, kể cả khi đổi tên. Tên mới sẽ thay tên cũ.
  - Hai người trùng họ tên trên hai máy khác nhau vẫn là hai dòng riêng.
  - Đổi máy, đổi trình duyệt, mở tab ẩn danh hoặc xóa dữ liệu trình duyệt thì được tính là người chơi mới.

## Khi bấm "Bắt đầu"

Trò chơi lưu họ tên và mã thiết bị lên Supabase (hàm `register_player`), **chờ máy chủ xác nhận rồi mới vào trạm 1**. Thường chỉ mất dưới 1 giây. Trong lúc chờ, nút hiện *“⏳ Đang lưu thông tin…”* và không bấm thêm được, nên không bị gửi trùng. Nếu mạng lỗi hoặc máy chủ không trả lời sau **8 giây**, trò chơi báo lỗi và cho bấm thử lại.

Người mới đăng ký mà chưa chơi xong sẽ **chưa** xuất hiện trên bảng xếp hạng. Họ chỉ có mặt trong bảng `players` trên Supabase.

> ⚠️ Mỗi lần sửa `supabase/schema.sql`, hãy chạy lại **toàn bộ** file trong SQL Editor **trước** khi đẩy code mới lên GitHub. Chạy lại nhiều lần vẫn an toàn, không mất dữ liệu.

---

## Bước 1. Tạo CSDL trên Supabase (khoảng 5 phút)

1. Vào <https://supabase.com>, đăng nhập bằng tài khoản GitHub, bấm **New project**. Đặt tên tùy ý, chọn Region **Southeast Asia (Singapore)**, gói **Free**.
2. Khi dự án tạo xong, mở **SQL Editor → New query**. Dán toàn bộ nội dung file [`supabase/schema.sql`](supabase/schema.sql) rồi bấm **Run**. Thấy dòng `Success` là xong.
3. Mở **Project Settings → API** (hoặc bấm nút **Connect** ở đầu trang) và chép 2 giá trị:
   - **Project URL**, dạng `https://abcdxyz.supabase.co`
   - Khóa **anon** (hoặc **publishable**, bắt đầu bằng `sb_publishable_`)
4. Dán 2 giá trị đó vào [`config.js`](config.js):

   ```js
   window.APP_CONFIG = {
     SUPABASE_URL: "https://abcdxyz.supabase.co",
     SUPABASE_KEY: "sb_publishable_xxxxxxxx"
   };
   ```

> ⚠️ **Tuyệt đối không** dán khóa `service_role` / `secret`, vì repo GitHub là công khai. Khóa anon/publishable thì công khai được: CSDL đã chặn đọc/ghi trực tiếp, chỉ cho gọi 3 hàm của trò chơi. Nếu lỡ dán khóa bí mật, trò chơi sẽ báo lỗi và không gửi gì đi.

## Bước 2. Chạy thử trên máy

Mở thư mục trong VS Code và chạy bằng tiện ích **Live Server** (chuột phải `index.html` → *Open with Live Server*). Cũng có thể chạy lệnh `npx serve .` rồi mở địa chỉ được in ra.

Chơi hết một lượt. Màn kết quả sẽ hiện dòng `🏆 Lượt này … điểm – hạng #…`. Bấm **Xem bảng xếp hạng** để kiểm tra.

> Khi chưa điền `config.js`, trò chơi vẫn chơi được, nhưng màn kết quả sẽ báo *“Chưa lưu được kết quả: chưa cấu hình máy chủ”*.

## Bước 3. Đưa lên GitHub Pages

1. Tạo repo mới trên <https://github.com/new> và chọn **Public** (GitHub Pages miễn phí chỉ dùng được với repo công khai).
2. Đẩy toàn bộ thư mục này lên repo. Có thể kéo thả file trên giao diện web của GitHub, hoặc dùng git:

   ```bash
   git init
   git add .
   git commit -m "Trò chơi Robot Tin học"
   git branch -M main
   git remote add origin https://github.com/<tên-github>/<tên-repo>.git
   git push -u origin main
   ```

3. Trong repo, vào **Settings → Pages**. Ở mục *Source* chọn **Deploy from a branch**, chọn nhánh **main**, thư mục **/ (root)**, rồi bấm **Save**.
4. Sau 1–2 phút, trò chơi chạy tại:
   - **Link gửi cho người tham gia:** `https://<tên-github>.github.io/<tên-repo>/`
   - **Link trình chiếu bảng xếp hạng:** `https://<tên-github>.github.io/<tên-repo>/#bang-xep-hang` (tự làm mới mỗi 15 giây)

Mỗi lần sửa code và đẩy lên lại, GitHub Pages tự cập nhật sau khoảng 1 phút.

---

## Trước mỗi tiết học

- [ ] Mở dashboard Supabase. Gói free **tạm dừng dự án sau khoảng 7 ngày không có hoạt động**. Nếu thấy *Paused*, bấm **Restore** và đợi vài phút.
- [ ] Mở link thật trên điện thoại và chơi thử một lượt.
- [ ] (Tùy chọn) Xóa dữ liệu chơi thử, xem mục bên dưới.

## Xuất file kết quả (dành cho giáo viên)

Trong **SQL Editor**, chạy lệnh sau, rồi bấm **Export → Download CSV** để tải về mở bằng Excel:

```sql
select rank as "Hạng", full_name as "Họ và tên",
       points as "Điểm", first_try as "Đúng ngay lần đầu",
       wrong_total as "Số lần sai", round(duration_ms / 1000.0) as "Thời gian (giây)",
       played_at as "Thời điểm"
from private.ranked()
order by rank;
```

## Xóa dữ liệu để bắt đầu tiết mới

```sql
truncate public.plays, public.players;
```

## Sửa câu hỏi

Câu hỏi nằm trong mảng `QUESTIONS` ở đầu thẻ `<script>` chính của [`index.html`](index.html). Mỗi câu có `question`, 4 `options`, `answer` (vị trí đáp án đúng, đếm từ 0) và `explain`. Thanh pin và cách tính điểm tự điều chỉnh theo số câu. Nếu thêm hoặc bớt câu, nhớ sửa phần chữ “4 trạm” và các ô Trạm 1–4 ở màn hình đầu. Máy chủ chấp nhận tối đa 20 câu.
