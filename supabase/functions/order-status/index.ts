import { createClient } from "npm:@supabase/supabase-js@2";

const allowedHeaders = "authorization, apikey, content-type, x-client-info";
function corsHeaders(req: Request) {
  const configured = Deno.env.get("ALLOWED_ORIGIN")?.split(",").map(x => x.trim()).filter(Boolean) ?? [];
  if (!configured.length) console.warn("ALLOWED_ORIGIN is not configured; temporarily allowing all origins");
  const origin = req.headers.get("origin") ?? "";
  const allowed = configured.length ? (!origin || configured.includes(origin)) : true;
  const headers: Record<string, string> = {
    "Access-Control-Allow-Headers": allowedHeaders,
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Content-Type": "application/json; charset=utf-8",
    "Vary": "Origin",
  };
  if (!configured.length) headers["Access-Control-Allow-Origin"] = "*";
  else if (origin && allowed) headers["Access-Control-Allow-Origin"] = origin;
  else if (origin) headers["Access-Control-Allow-Origin"] = "null";
  return headers;
}
function reply(req: Request, status: number, body: unknown) {
  return new Response(JSON.stringify(body), { status, headers: corsHeaders(req) });
}
const isUuid = (v: unknown) => typeof v === "string" && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(v);

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
    const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!url || !key) return reply(req, 500, { error: "server_configuration_missing" });
    let body: any;
    try { body = await req.json(); } catch { return reply(req, 400, { error: "invalid_json" }); }
    const tableId = body?.table_id;
    const token = body?.session_token;
    if (!isUuid(tableId) || !isUuid(token)) return reply(req, 400, { error: "invalid_table_or_session" });
    const db = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
    const { data: table, error: tableError } = await db.from("cafe_tables")
      .select("id,name,is_active").eq("id", tableId).maybeSingle();
    if (tableError) throw tableError;
    if (!table || !table.is_active) return reply(req, 404, { active: false });

    const { data: order, error: orderError } = await db.from("orders")
      .select("id,status,customer_session_token,total,estimated_wait_minutes,created_at,updated_at")
      .eq("table_id", tableId).not("status", "in", '("settled","cancelled")').maybeSingle();
    if (orderError) throw orderError;
    if (!order) {
      const { data: closedOrder, error: closedError } = await db.from("orders")
        .select("id,status,customer_session_token,total,estimated_wait_minutes,created_at,updated_at")
        .eq("table_id", tableId).eq("customer_session_token", token)
        .in("status", ["settled", "cancelled"]).order("updated_at", { ascending: false }).limit(1).maybeSingle();
      if (closedError) throw closedError;
      if (!closedOrder) return reply(req, 200, { active: false, table: { id: table.id, name: table.name } });
      const { data: closedItems, error: closedItemsError } = await db.from("order_items")
        .select("item_name,unit_price,quantity,line_total").eq("order_id", closedOrder.id);
      if (closedItemsError) throw closedItemsError;
      return reply(req, 200, { active: false, owned: true, table: { id: table.id, name: table.name }, order: closedOrder, items: closedItems ?? [] });
    }
    if (order.customer_session_token !== token) return reply(req, 200, { active: true, owned: false });
    const { data: items, error: itemsError } = await db.from("order_items")
      .select("item_name,unit_price,quantity,line_total").eq("order_id", order.id);
    if (itemsError) throw itemsError;
    return reply(req, 200, { active: true, owned: true, table: { id: table.id, name: table.name }, order, items: items ?? [] });
  } catch (error) {
    console.error("order-status failed", error instanceof Error ? error.message : "unknown_error");
    return reply(req, 500, { error: "order_status_unavailable" });
  }
});
