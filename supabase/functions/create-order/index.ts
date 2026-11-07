import { createClient } from "npm:@supabase/supabase-js@2";

const allowedHeaders = "authorization, apikey, content-type, x-client-info";
function corsHeaders(req: Request) {
  const configured = Deno.env.get("ALLOWED_ORIGIN")?.split(",").map(x => x.trim()).filter(Boolean) ?? [];
  if (!configured.length) console.warn("ALLOWED_ORIGIN is not configured; temporarily allowing all origins");
  const origin = req.headers.get("origin") ?? "";
  const allowed = configured.length ? configured.includes(origin) : true;
  return {
    "Access-Control-Allow-Origin": configured.length ? (allowed ? origin : "null") : "*",
    "Access-Control-Allow-Headers": allowedHeaders,
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Content-Type": "application/json; charset=utf-8",
    "Vary": "Origin",
  };
}
function reply(req: Request, status: number, body: unknown) {
  return new Response(JSON.stringify(body), { status, headers: corsHeaders(req) });
}
function validUuid(value: unknown): value is string {
  return typeof value === "string" && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}
async function sha256(value: string) {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)].map(x => x.toString(16).padStart(2, "0")).join("");
}

Deno.serve(async (req: Request) => {
  const cors = corsHeaders(req);
  if (req.method === "OPTIONS") {
    if (cors["Access-Control-Allow-Origin"] === "null") return new Response("origin_not_allowed", { status: 403, headers: cors });
    return new Response("ok", { headers: cors });
  }
  if (req.method !== "POST") return reply(req, 405, { error: "method_not_allowed" });
  if (cors["Access-Control-Allow-Origin"] === "null") return reply(req, 403, { error: "origin_not_allowed" });

  try {
    const url = Deno.env.get("SUPABASE_URL");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const salt = Deno.env.get("RATE_LIMIT_SALT");
    if (!url || !serviceKey || !salt) return reply(req, 500, { error: "server_configuration_missing" });

    let input: any;
    try { input = await req.json(); } catch { return reply(req, 400, { error: "invalid_json" }); }
    const tableId = input?.table_id;
    const sessionToken = input?.session_token;
    const items = input?.items;
    if (!validUuid(tableId) || !validUuid(sessionToken)) return reply(req, 400, { error: "invalid_table_or_session" });
    if (!Array.isArray(items) || items.length < 1 || items.length > 30) return reply(req, 400, { error: "invalid_items" });
    for (const row of items) {
      if (!validUuid(row?.menu_item_id)) return reply(req, 400, { error: "invalid_item_id" });
      if (!Number.isInteger(row?.quantity) || row.quantity < 1 || row.quantity > 20) return reply(req, 400, { error: "invalid_quantity" });
    }

    const forwarded = req.headers.get("x-forwarded-for") ?? "";
    const ip = forwarded.split(",")[0].trim();
    if (!ip) return reply(req, 400, { error: "client_ip_unavailable" });
    const rateKey = await sha256(salt + ip);
    const now = new Date();
    const windowMs = 10 * 60 * 1000;
    const windowStart = new Date(Math.floor(now.getTime() / windowMs) * windowMs).toISOString();

    const db = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
    const { data: requestCount, error: rateError } = await db.rpc("consume_order_rate_limit", {
      p_key: rateKey, p_window_start: windowStart,
    });
    if (rateError) throw rateError;
    if (Number(requestCount) > 8) return reply(req, 429, { error: "rate_limited" });
    if (Number(requestCount) === 1) {
      await db.from("order_rate_limits").delete().lt("window_start", new Date(now.getTime() - 86400000).toISOString());
    }

    const { data, error } = await db.rpc("customer_place_or_extend_order", {
      p_table_id: tableId,
      p_session_token: sessionToken,
      p_items: items,
      p_note: String(input?.customer_note ?? input?.note ?? "").slice(0, 500),
    });
    if (error) {
      const message = String(error.message ?? error.details ?? "");
      for (const code of ["table_occupied", "order_not_editable", "session_has_other_active_order"]) {
        if (message.includes(code)) return reply(req, 409, { error: code });
      }
      if (message.includes("menu_item_unavailable")) return reply(req, 400, { error: "menu_item_unavailable" });
      if (message.includes("invalid_items")) return reply(req, 400, { error: "invalid_items" });
      throw error;
    }
    return reply(req, data?.resumed ? 200 : 201, data);
  } catch (error) {
    console.error("create-order failed", error instanceof Error ? error.message : "unknown_error");
    return reply(req, 500, { error: "order_creation_failed" });
  }
});
