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
| `supabase/functions/` | Backend: Edge Functions viết bằng TypeScript, tự deploy khi push (xem mục *Backend*) |
| `supabase/config.toml` | Cấu hình Supabase CLI cho Edge Functions |
| `.github/workflows/deploy-functions.yml` | GitHub Actions đưa Edge Functions lên Supabase |

## Cách tính điểm và xếp hạng

- Tổng điểm tối đa là **1000**. Mỗi trạm tối đa **250 điểm**, mỗi lần chọn sai bị trừ **75 điểm**:

  | Kết quả ở mỗi trạm | Điểm |
  |---|---|
  | Đúng ngay lần đầu | **250** |
  | Sai 1 lần rồi đúng | **175** |
  | Sai 2 lần rồi đúng | **100** |
  | Sai 3 lần rồi đúng | **25** |

  Nếu thêm hoặc bớt câu hỏi, tổng tối đa vẫn là 1000 và được chia đều cho các trạm. Công thức nằm ở hàm `private.calc_points` trong `supabase/schema.sql`.
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

## Xóa bảng xếp hạng để bắt đầu tiết mới (nút dành cho giáo viên)

1. **Đặt mật khẩu quản trị một lần.** Trong SQL Editor, chạy lệnh sau (ít nhất 8 ký tự). Chạy lại lệnh này để đổi mật khẩu.
   ```sql
   select private.set_admin_password('mật-khẩu-của-bạn');
   ```
   Mật khẩu chỉ lưu dạng mã hóa trong Supabase, không nằm trong code. Đừng ghi mật khẩu vào file nào trong repo.
2. **Mở link quản trị** `https://<tên-github>.github.io/<tên-repo>/#quan-tri`. Bảng xếp hạng sẽ có thêm nút đỏ **🗑 Xóa bảng xếp hạng**. Người chơi mở link thường không thấy nút này.
3. Bấm nút, nhập mật khẩu rồi bấm **Xóa vĩnh viễn**. Bảng trở về trống, và mọi máy đang mở bảng xếp hạng sẽ cập nhật trong vòng 15 giây.

- ⚠️ Đây là **xóa vĩnh viễn**: toàn bộ người chơi và lượt chơi bị xóa khỏi CSDL, **không lưu trữ và không khôi phục được**.
- Nhập sai mật khẩu **5 lần liên tiếp** thì bị khóa **10 phút**. Đặt lại mật khẩu bằng lệnh ở bước 1 sẽ mở khóa ngay.
- Người đang chơi dở lúc xóa vẫn chơi bình thường. Kết quả của họ sẽ hiện trên bảng mới.
- Cũng có thể xóa thẳng trong SQL Editor (không cần mật khẩu): `truncate public.plays, public.players;`

## Backend (Supabase Edge Functions)

GitHub Pages chỉ chứa trang tĩnh, không chạy được code máy chủ. Vì vậy backend chạy trên **Supabase Edge Functions** (TypeScript, gói Free khoảng 500.000 lượt gọi/tháng, **0đ**). Code nằm trong repo ở `supabase/functions/<tên-hàm>/index.ts`. Mỗi lần push thay đổi trong thư mục này lên `main`, **GitHub Actions** tự đưa code lên Supabase.

Chỉ cần dùng Edge Function khi hàm SQL không làm được: gọi API bên ngoài, gửi email, xử lý file, hoặc cần khóa bí mật. Logic chỉ đọc/ghi dữ liệu thì cứ viết hàm SQL trong `schema.sql` như hiện nay.

### Cài đặt một lần

1. Vào <https://supabase.com/dashboard/account/tokens> và bấm **Generate new token**, rồi chép token.
2. Trên GitHub, mở repo, vào **Settings → Secrets and variables → Actions → New repository secret**. Đặt tên `SUPABASE_ACCESS_TOKEN` và dán token vào.
3. Mở tab **Actions**, chọn *Deploy Supabase Edge Functions* rồi bấm **Run workflow** (hoặc push một thay đổi trong `supabase/functions/`). Thấy dấu ✅ xanh là xong.
4. Kiểm tra: mở trò chơi, nhấn F12 để mở Console và gõ `callFunction("health").then(console.log)`. Kết quả đúng là `{ok: true, time: "…"}`.

### Thêm một hàm mới

1. Tạo `supabase/functions/<tên-hàm>/index.ts` (chép từ `health/index.ts`). Dùng `corsHeaders` và `json()` trong `_shared/cors.ts` để trang web gọi được.
2. Thêm vào `supabase/config.toml`:
   ```toml
   [functions.<tên-hàm>]
   verify_jwt = false
   ```
   Khóa publishable (`sb_publishable_…`) không phải JWT, nên phải tắt kiểm tra JWT ở cổng. Hàm nào cần bảo vệ thì tự kiểm tra trong code, ví dụ bằng mật khẩu quản trị.
3. Trong `index.html`, gọi bằng `callFunction("<tên-hàm>", { ...dữ liệu }, 8000)`. Hàm này trả về Promise giống `rpc()`.
4. Push lên `main`, GitHub Actions sẽ tự deploy.

- **Khóa bí mật** (khóa API bên ngoài, khóa `service_role`…) **không bao giờ** được ghi vào repo. Đặt khóa bằng `npx supabase secrets set TEN_KHOA=giá-trị --remote=nsrtpgxcnloqmuntaehu` (cần đăng nhập trước bằng `npx supabase login`), rồi đọc trong hàm bằng `Deno.env.get("TEN_KHOA")`. Trong Edge Function, Supabase tự cung cấp sẵn `SUPABASE_URL` và khóa service role.
- **Chạy thử trên máy** (cần cài Docker Desktop): chạy `npx supabase start`, rồi `npx supabase functions serve`. Sau đó mở `http://localhost:54321/functions/v1/health`.

## Sửa câu hỏi

Câu hỏi nằm trong mảng `QUESTIONS` ở đầu thẻ `<script>` chính của [`index.html`](index.html). Mỗi câu có `question`, 4 `options`, `answer` (vị trí đáp án đúng, đếm từ 0) và `explain`. Thanh pin và cách tính điểm tự điều chỉnh theo số câu. Nếu thêm hoặc bớt câu, nhớ sửa phần chữ “4 trạm” và các ô Trạm 1–4 ở màn hình đầu. Máy chủ chấp nhận tối đa 20 câu.
