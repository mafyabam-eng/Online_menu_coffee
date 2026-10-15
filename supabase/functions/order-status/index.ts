import { createClient } from "npm:@supabase/supabase-js@2";
const cors={"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization, apikey, content-type, x-client-info","Access-Control-Allow-Methods":"POST, OPTIONS","Content-Type":"application/json; charset=utf-8"};
const reply=(status:number,body:unknown)=>new Response(JSON.stringify(body),{status,headers:cors});
Deno.serve(async(req:Request)=>{
 if(req.method==="OPTIONS")return new Response("ok",{headers:cors});
 if(req.method!=="POST")return reply(405,{error:"method_not_allowed"});
 try{
  const db=createClient(Deno.env.get("SUPABASE_URL")!,Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,{auth:{persistSession:false}});
  const body=await req.json(),qr=String(body.qr_token||""),token=String(body.session_token||"");
  if(!/^[0-9a-f-]{36}$/i.test(qr))return reply(400,{error:"invalid_qr"});
  const {data:table,error:te}=await db.from("cafe_tables").select("id,name,is_active").eq("qr_token",qr).maybeSingle();
  if(te)throw te;if(!table||!table.is_active)return reply(404,{active:false});
  const {data:order,error:oe}=await db.from("orders").select("id,status,customer_session_token,total,estimated_wait_minutes,created_at,updated_at").eq("table_id",table.id).not("status","in",'("settled","cancelled")').maybeSingle();
  if(oe)throw oe;if(!order)return reply(200,{active:false,table:{id:table.id,name:table.name}});
  if(order.customer_session_token!==token)return reply(200,{active:true,owned:false,table:{id:table.id,name:table.name}});
  const {data:lines,error:le}=await db.from("order_items").select("item_name,unit_price,quantity,line_total").eq("order_id",order.id);
  if(le)throw le;return reply(200,{active:true,owned:true,table:{id:table.id,name:table.name},order,items:lines||[]});
 }catch(e){console.error("order-status failed",e);return reply(500,{error:"order_status_unavailable"});}
});