// Webhooks use a Vault-verified secret. Receipt checks require a live superadmin session.
// No names, message bodies or raw tokens are retained in diagnostics.
const cors={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization,apikey,content-type,x-webhook-secret','Access-Control-Allow-Methods':'POST,OPTIONS'};
const json=(data:unknown,status=200)=>Response.json(data,{status,headers:cors});
const codes=new Set(['DeviceNotRegistered','MessageTooBig','MessageRateExceeded','MismatchSenderId','InvalidCredentials']);
const safeCode=(value:unknown)=>typeof value==='string'&&codes.has(value)?value:'ProviderError';
const hash=async(token:string)=>Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(token))),x=>x.toString(16).padStart(2,'0')).join('');
Deno.serve(async(req:Request)=>{
 if(req.method==='OPTIONS')return new Response(null,{status:204,headers:cors});
 if(req.method!=='POST')return json({error:'Method not allowed'},405);
 const url=Deno.env.get('SUPABASE_URL'),key=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
 if(!url||!key)return json({error:'Not configured'},503);
 const headers={apikey:key,Authorization:`Bearer ${key}`,'Content-Type':'application/json'};
 const call=async(path:string,init:RequestInit={})=>{const r=await fetch(url+'/rest/v1/'+path,{...init,headers:{...headers,...init.headers},signal:AbortSignal.timeout(15000)});if(!r.ok)throw Error('Database request failed');return r.status===204?null:await r.json()};
 const patch=async(id:string,data:Record<string,unknown>)=>call('push_delivery_log?id=eq.'+encodeURIComponent(id),{method:'PATCH',headers:{Prefer:'return=minimal'},body:JSON.stringify({...data,updated_at:new Date().toISOString()})});
 const supplied=req.headers.get('x-webhook-secret');
 try{
  if(supplied && (supplied.length>256 || await call('rpc/verify_activity_push_secret',{method:'POST',body:JSON.stringify({p_secret:supplied})})!==true))return json({error:'Unauthorized'},401);
  const input=await req.json();
  if(!supplied || input.action==='check_receipts'){
   if(!supplied){
   const bearer=req.headers.get('Authorization');if(!bearer?.startsWith('Bearer '))return json({error:'Unauthorized'},401);
   const auth=await fetch(url+'/rest/v1/rpc/get_verified_profile',{method:'POST',headers:{...headers,Authorization:bearer},body:'{}',signal:AbortSignal.timeout(15000)});
   if(!auth.ok)return json({error:'Unauthorized'},401);const profile=await auth.json();if(!profile?.is_super_admin&&profile?.admin_level!=='super')return json({error:'Forbidden'},403);
   }
   const body=input;if(body.action!=='check_receipts')return json({error:'Invalid action'},400);
   const now=Date.now(),iso=(age:number)=>new Date(now-age).toISOString();
   await call('push_delivery_log?created_at=lt.'+iso(30*86400000),{method:'DELETE',headers:{Prefer:'return=minimal'}});
   await call('push_delivery_log?state=eq.accepted&created_at=lt.'+iso(86400000),{method:'PATCH',headers:{Prefer:'return=minimal'},body:JSON.stringify({state:'receipt_expired',error_code:'ReceiptExpired',updated_at:iso(0)})});
   const rows=await call('push_delivery_log?state=eq.accepted&created_at=lte.'+iso(15*60000)+'&created_at=gte.'+iso(86400000)+'&updated_at=lt.'+iso(60000)+'&select=id,receipt_id,recipient_phone,device_key&order=updated_at.asc,created_at.asc&limit=100');
   if(!rows.length)return json({checked:0});
   const response=await fetch('https://exp.host/--/api/v2/push/getReceipts',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({ids:rows.map((r:{receipt_id:string})=>r.receipt_id)}),signal:AbortSignal.timeout(15000)});
   if(!response.ok)return json({error:'Receipt provider unavailable'},502);const receipts=(await response.json()).data;if(!receipts||typeof receipts!=='object'||Array.isArray(receipts))return json({error:'Invalid receipt response'},502);
   for(const row of rows){const receipt=receipts[row.receipt_id];if(!receipt){await patch(row.id,{error_code:'ReceiptPending'});continue}
    if(receipt.status==='ok')await patch(row.id,{state:'provider_accepted',error_code:null});
    else if(receipt.status==='error'){const code=safeCode(receipt.details?.error);await patch(row.id,{state:'failed',error_code:code});if(code==='DeviceNotRegistered'){
     const devices=await call('push_devices?phone=eq.'+encodeURIComponent(row.recipient_phone)+'&select=token');for(const d of devices)if(await hash(d.token)===row.device_key)await call('push_devices?token=eq.'+encodeURIComponent(d.token),{method:'DELETE',headers:{Prefer:'return=minimal'}});
    }}else await patch(row.id,{error_code:'InvalidReceipt'});
   }return json({checked:rows.length});
  }
  if(input.action!=='drain' && !(input.type==='INSERT'&&input.table==='notifications'))return json({error:'Invalid action'},400);
  const claimed=await call('rpc/claim_push_batch',{method:'POST',body:'{}'});
  if(!claimed.length)return json({attempted:0});
  const started=await call('rpc/start_push_batch',{method:'POST',body:JSON.stringify({p_jobs:claimed.map((d:any)=>({id:d.id,lease_id:d.lease_id}))})});
  const batch=claimed.filter((d:any)=>started.includes(d.id));
  if(!batch.length)return json({attempted:0});
  let results;
  const result=(d:any,state:string,error_code:string|null=null,receipt_id:string|null=null)=>({id:d.id,lease_id:d.lease_id,state,error_code,receipt_id});
  try{
   const sent=await fetch('https://exp.host/--/api/v2/push/send',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(batch.map((d:any)=>({to:d.token,title:String(d.title||'ჩემი უბანი').slice(0,80),body:String(d.body||'ახალი შეტყობინება').slice(0,180),sound:'default',channelId:'activity',data:{kind:'activity',notificationId:d.notification_id}}))),signal:AbortSignal.timeout(15000)});
   if(sent.status===429)results=batch.map((d:any)=>result(d,'retry','MessageRateExceeded'));
   else if(!sent.ok)results=batch.map((d:any)=>result(d,sent.status>=500?'unknown':'failed','ProviderHttpError'));
   else{
    const payload=await sent.json();if(!Array.isArray(payload.data)||payload.data.length!==batch.length)throw Error('Invalid response');
    results=batch.map((d:any,i:number)=>{const t=payload.data[i];if(t?.status==='ok'&&typeof t.id==='string'&&t.id.length>0&&t.id.length<=150)return result(d,'accepted',null,t.id);if(t?.status!=='error')return result(d,'unknown','ResponseUnknown');const code=safeCode(t.details?.error);return result(d,code==='MessageRateExceeded'?'retry':'failed',code)});
   }
  }catch{results=batch.map((d:any)=>result(d,'unknown','ResponseUnknown'))}
  await call('rpc/finish_push_batch',{method:'POST',body:JSON.stringify({p_results:results})});
  return json({attempted:batch.length});
 }catch{return json({error:'Push operation failed'},502)}
});
