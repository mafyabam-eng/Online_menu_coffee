import { createClient } from "npm:@supabase/supabase-js@2";
const cors={"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization, apikey, content-type, x-client-info","Access-Control-Allow-Methods":"POST, OPTIONS","Content-Type":"application/json; charset=utf-8"};
const reply=(status:number,body:unknown)=>new Response(JSON.stringify(body),{status,headers:cors});
Deno.serve(async(req:Request)=>{
 if(req.method==="OPTIONS")return new Response("ok",{headers:cors});
 if(req.method!=="POST")return reply(405,{error:"method_not_allowed"});
 try{
  const url=Deno.env.get("SUPABASE_URL"),key=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if(!url||!key)return reply(500,{error:"server_configuration_missing"});
  const db=createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false}});
  const input=await req.json(),tableId=String(input.table_id||""),sessionToken=String(input.session_token||""),raw=Array.isArray(input.items)?input.items:[];
  if(!/^[0-9a-f-]{36}$/i.test(tableId)||!/^[0-9a-f-]{36}$/i.test(sessionToken))return reply(400,{error:"invalid_table_or_session"});
  if(!raw.length||raw.length>30)return reply(400,{error:"invalid_items"});
  const requested=new Map<string,number>();
  for(const row of raw){if(!/^[0-9a-f-]{36}$/i.test(String(row?.menu_item_id||"")))return reply(400,{error:"invalid_item_id"});const q=Number(row.quantity);if(!Number.isInteger(q)||q<1||q>20)return reply(400,{error:"invalid_quantity"});requested.set(row.menu_item_id,(requested.get(row.menu_item_id)||0)+q);}
  const {data:table,error:te}=await db.from("cafe_tables").select("id,is_active").eq("id",tableId).maybeSingle();if(te)throw te;if(!table||!table.is_active)return reply(400,{error:"table_unavailable"});
  const {data:existing,error:ee}=await db.from("orders").select("id,status,customer_session_token,subtotal,discount_amount,total,estimated_wait_minutes,created_at").eq("table_id",tableId).not("status","in",'("settled","cancelled")').maybeSingle();if(ee)throw ee;
  if(existing){if(existing.customer_session_token!==sessionToken)return reply(409,{error:"table_occupied"});const {data:oldItems,error:oe}=await db.from("order_items").select("*").eq("order_id",existing.id);if(oe)throw oe;return reply(200,{order:existing,items:oldItems||[],resumed:true});}
  const ids=[...requested.keys()];
  const {data:menu,error:me}=await db.from("menu_items").select("id,name,price,serving_minutes,is_active").in("id",ids);if(me)throw me;if(!menu||menu.length!==ids.length||menu.some((x:any)=>!x.is_active))return reply(400,{error:"menu_item_unavailable"});
  const map=new Map(menu.map((x:any)=>[x.id,x]));
  const lines=ids.map(id=>{const x:any=map.get(id),quantity=requested.get(id)!;return {menu_item_id:x.id,item_name:x.name,unit_price:Number(x.price),quantity,serving_minutes:Number(x.serving_minutes),line_total:Number(x.price)*quantity};});
  const subtotal=lines.reduce((s,x)=>s+x.line_total,0);
  const {data:settings,error:se}=await db.from("cafe_settings").select("menu_discount_percent").eq("id",true).single();if(se)throw se;
  const discount=Math.round(subtotal*Number(settings.menu_discount_percent||0)/100),total=Math.max(0,subtotal-discount);
  const {data:active,error:ae}=await db.from("orders").select("id").not("status","in",'("settled","cancelled")');if(ae)throw ae;
  let queueWait=0;const idsActive=(active||[]).map((x:any)=>x.id);
  if(idsActive.length){const {data:q,error:qe}=await db.from("order_items").select("order_id,serving_minutes,quantity").in("order_id",idsActive);if(qe)throw qe;const waits=new Map<string,number>();for(const x of q||[])waits.set(x.order_id,Math.max(waits.get(x.order_id)||0,Number(x.serving_minutes)*Number(x.quantity)));queueWait=[...waits.values()].reduce((s,n)=>s+n,0);}
  const wait=queueWait+lines.reduce((s,x)=>s+x.serving_minutes*x.quantity,0);
  const {data:order,error:oe}=await db.from("orders").insert({table_id:tableId,customer_session_token:sessionToken,status:"pending",subtotal,discount_amount:discount,total,estimated_wait_minutes:wait,customer_note:String(input.customer_note||"").slice(0,500)}).select("id,status,customer_session_token,subtotal,discount_amount,total,estimated_wait_minutes,created_at").single();
  if(oe){if(oe.code==="23505")return reply(409,{error:"table_occupied"});throw oe;}
  const rows=lines.map(x=>({...x,order_id:order.id}));const {error:le}=await db.from("order_items").insert(rows);if(le){await db.from("orders").delete().eq("id",order.id);throw le;}
  return reply(201,{order,items:rows,resumed:false});
 }catch(e){console.error("create-order failed",e);return reply(500,{error:"order_creation_failed"});}
});