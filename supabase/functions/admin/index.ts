// API cho trang quản trị admin.html.
// Gọi: POST {SUPABASE_URL}/functions/v1/admin  với body JSON { action, ... }
//
//   { action: "login", username, password }          → { token, expires_at }
//   { action: "logout", token }                       → { ok: true }
//   { action: "list", token }                         → { players: [...], game: { started, started_at, ready } }
//   { action: "game_start", token }                   → { game: { started: true, started_at } }
//   { action: "game_stop", token }                    → { game: { started: false, started_at: null } }
//   { action: "update", token, player_id, full_name } → { player: { player_id, full_name } }
//   { action: "delete", token, player_id }            → { full_name }
//   { action: "delete_all", token }                   → { deleted }
//
// Lỗi trả về { error: "thông báo tiếng Việt" } kèm mã HTTP: 400 dữ liệu sai,
// 401 sai đăng nhập / phiên hết hạn, 404 không tìm thấy, 500 lỗi máy chủ.
//
// Hàm này gọi các hàm SQL admin_* (supabase/schema.sql) bằng khóa bí mật của máy chủ;
// trình duyệt không có khóa này nên không gọi thẳng được các hàm đó.
import { corsHeaders, json } from "../_shared/cors.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_KEY = pickServiceKey();
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const TOKEN_RE = /^[0-9a-f]{64}$/;

class HttpError extends Error {
  status: number;
  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}

// Supabase tự cấp khóa cho Edge Function: khóa mới (SUPABASE_SECRET_KEYS, dạng JSON)
// hoặc khóa cũ (SUPABASE_SERVICE_ROLE_KEY). Dùng khóa nào có trước.
function pickServiceKey(): string {
  const raw = Deno.env.get("SUPABASE_SECRET_KEYS");
  if (raw) {
    try {
      const keys = JSON.parse(raw) as Record<string, string>;
      const key = keys.default ?? Object.values(keys)[0];
      if (key) return key;
    } catch {
      // không đọc được thì thử khóa cũ bên dưới
    }
  }
  return Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
}

// Gọi một hàm SQL qua PostgREST bằng khóa bí mật
async function callSql(fn: string, args: Record<string, unknown>): Promise<unknown> {
  const headers: Record<string, string> = { "Content-Type": "application/json", apikey: SERVICE_KEY };
  if (!SERVICE_KEY.startsWith("sb_secret_")) headers.Authorization = `Bearer ${SERVICE_KEY}`;  // khóa cũ dạng JWT

  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${fn}`, {
    method: "POST",
    headers,
    body: JSON.stringify(args),
  });
  const text = await res.text();
  let data: any = null;
  try {
    data = text ? JSON.parse(text) : null;
  } catch {
    // giữ nguyên text để ghi log
  }
  if (res.ok) return data;

  // Lỗi do hàm SQL chủ động báo (raise exception): có mã SQLSTATE trong "code"
  const code = typeof data?.code === "string" ? data.code : "";
  const message = typeof data?.message === "string" ? data.message : "";
  if (code === "PT401") throw new HttpError(401, message);
  if (code === "PT404") throw new HttpError(404, message);
  if (code === "P0001" && message) throw new HttpError(400, message);   // vd. "Họ tên không hợp lệ"

  // Còn lại là lỗi cấu hình / máy chủ: ghi log chi tiết, chỉ báo chung cho trình duyệt
  console.error(`SQL ${fn} lỗi ${res.status}:`, text.slice(0, 500));
  throw new HttpError(500, "Lỗi máy chủ, vui lòng thử lại sau");
}

function str(value: unknown, field: string, maxLen: number): string {
  if (typeof value !== "string" || !value.trim()) throw new HttpError(400, `Thiếu ${field}`);
  if (value.length > maxLen) throw new HttpError(400, `${field} quá dài`);
  return value;
}

function token(body: Record<string, unknown>): string {
  const t = body.token;
  if (typeof t !== "string" || !TOKEN_RE.test(t)) {
    throw new HttpError(401, "Phiên đăng nhập đã hết hạn, vui lòng đăng nhập lại");
  }
  return t;
}

function playerId(body: Record<string, unknown>): string {
  const id = body.player_id;
  if (typeof id !== "string" || !UUID_RE.test(id)) throw new HttpError(400, "Mã người chơi không hợp lệ");
  return id;
}

async function handle(body: Record<string, unknown>): Promise<unknown> {
  switch (body.action) {
    case "login": {
      const rows = await callSql("admin_login", {
        p_username: str(body.username, "tên đăng nhập", 64),
        p_password: str(body.password, "mật khẩu", 200),
      }) as { ok: boolean; message: string; token: string; expires_at: string }[];
      const r = rows?.[0];
      if (!r) throw new HttpError(500, "Máy chủ không phản hồi kết quả");
      if (!r.ok) throw new HttpError(401, r.message);
      return { token: r.token, expires_at: r.expires_at };
    }
    case "logout":
      await callSql("admin_logout", { p_token: token(body) });
      return { ok: true };
    case "list": {
      // Kiểm tra phiên trước (admin_list_players báo 401 nếu sai), rồi mới lấy trạng thái trò chơi
      const players = await callSql("admin_list_players", { p_token: token(body) });
      const game = (await callSql("get_game_status", {}) as unknown[])?.[0] ?? null;
      return { players, game };
    }
    case "game_start":
    case "game_stop": {
      const rows = await callSql("admin_set_game", {
        p_token: token(body),
        p_started: body.action === "game_start",
      }) as unknown[];
      return { game: rows?.[0] ?? null };
    }
    case "update": {
      const rows = await callSql("admin_update_player", {
        p_token: token(body),
        p_player_id: playerId(body),
        p_full_name: str(body.full_name, "họ tên", 200),
      }) as unknown[];
      return { player: rows?.[0] ?? null };
    }
    case "delete": {
      const rows = await callSql("admin_delete_player", {
        p_token: token(body),
        p_player_id: playerId(body),
      }) as { full_name: string }[];
      return { full_name: rows?.[0]?.full_name ?? "" };
    }
    case "delete_all": {
      const rows = await callSql("admin_delete_all", { p_token: token(body) }) as { deleted: number }[];
      return { deleted: rows?.[0]?.deleted ?? 0 };
    }
    default:
      throw new HttpError(400, "Thao tác không hợp lệ");
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Chỉ hỗ trợ POST" }, 405);
  if (!SUPABASE_URL || !SERVICE_KEY) {
    console.error("Thiếu SUPABASE_URL hoặc khóa bí mật trong biến môi trường");
    return json({ error: "Máy chủ chưa được cấu hình" }, 500);
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
    if (!body || typeof body !== "object" || Array.isArray(body)) throw new Error();
  } catch {
    return json({ error: "Dữ liệu gửi lên không hợp lệ" }, 400);
  }

  try {
    return json(await handle(body));
  } catch (err) {
    if (err instanceof HttpError) return json({ error: err.message }, err.status);
    console.error("admin lỗi:", err);
    return json({ error: "Lỗi máy chủ, vui lòng thử lại sau" }, 500);
  }
});
