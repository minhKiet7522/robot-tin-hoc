// Hàm thử: kiểm tra backend đã deploy và gọi được từ trình duyệt.
// Gọi: POST/GET {SUPABASE_URL}/functions/v1/health
import { corsHeaders, json } from "../_shared/cors.ts";

Deno.serve((req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  return json({ ok: true, time: new Date().toISOString() });
});
