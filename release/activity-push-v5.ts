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
 let notificationId:string|null=null,recipient:string|null=null;
 const supplied=req.headers.get('x-webhook-secret');
 try{
  if(!supplied){
   const bearer=req.headers.get('Authorization');if(!bearer?.startsWith('Bearer '))return json({error:'Unauthorized'},401);
   const auth=await fetch(url+'/rest/v1/rpc/get_verified_profile',{method:'POST',headers:{...headers,Authorization:bearer},body:'{}',signal:AbortSignal.timeout(15000)});
   if(!auth.ok)return json({error:'Unauthorized'},401);const profile=await auth.json();if(!profile?.is_super_admin&&profile?.admin_level!=='super')return json({error:'Forbidden'},403);
   const body=await req.json();if(body.action!=='check_receipts')return json({error:'Invalid action'},400);
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
  if(supplied.length>256)return json({error:'Unauthorized'},401);
  if(await call('rpc/verify_activity_push_secret',{method:'POST',body:JSON.stringify({p_secret:supplied})})!==true)return json({error:'Unauthorized'},401);
  const event=await req.json();if(event.type!=='INSERT'||event.table!=='notifications'||!event.record?.id)return json({ignored:true});
  const [record]=await call('notifications?id=eq.'+encodeURIComponent(event.record.id)+'&select=recipient_phone');if(!record)return json({error:'Missing event'},404);notificationId=event.record.id;recipient=record.recipient_phone;
  const create=async(deviceKey:string,state:string,error_code:string|null=null)=>call('push_delivery_log?on_conflict=notification_id,device_key',{method:'POST',headers:{Prefer:'resolution=ignore-duplicates,return=representation'},body:JSON.stringify({notification_id:event.record.id,recipient_phone:record.recipient_phone,device_key:deviceKey,state,error_code})});
  const allowed=await call('rpc/push_delivery_allowed',{method:'POST',body:JSON.stringify({p_notification_id:event.record.id})});
  if(allowed!==true){await create('event','suppressed','Preferences');return json({suppressed:true})}
  const devices=await call('push_devices?phone=eq.'+encodeURIComponent(record.recipient_phone)+'&select=token');
  if(!devices.length){await create('event','no_device','NoDevice');return json({devices:0})}
  let attempted=0;
  for(let i=0;i<devices.length;i+=100){
   const batch=[];for(const device of devices.slice(i,i+100)){const [log]=await create(await hash(device.token),'processing');if(log)batch.push({token:device.token,id:log.id})}
   if(!batch.length)continue;attempted+=batch.length;
   try{
    const sent=await fetch('https://exp.host/--/api/v2/push/send',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(batch.map(d=>({to:d.token,title:'ჩემი უბანი',body:'ახალი აქტივობა გაქვს. გახსენი აპი.',sound:'default',channelId:'activity',data:{kind:'activity',notificationId:event.record.id}}))),signal:AbortSignal.timeout(15000)});
    if(!sent.ok){for(const d of batch)await patch(d.id,{state:'failed',error_code:'ProviderHttpError'});continue}
    const payload=await sent.json();if(!Array.isArray(payload.data)||payload.data.length!==batch.length)throw Error('Invalid push response');
    for(let j=0;j<batch.length;j++){const ticket=payload.data[j],device=batch[j];if(ticket.status==='ok'&&typeof ticket.id==='string'&&ticket.id.length<=150)await patch(device.id,{state:'accepted',receipt_id:ticket.id});
     else{const code=safeCode(ticket.details?.error);await patch(device.id,{state:'failed',error_code:code});if(code==='DeviceNotRegistered')await call('push_devices?token=eq.'+encodeURIComponent(device.token),{method:'DELETE',headers:{Prefer:'return=minimal'}})}
    }
   }catch{for(const d of batch)await call('push_delivery_log?id=eq.'+encodeURIComponent(d.id)+'&state=eq.processing',{method:'PATCH',headers:{Prefer:'return=minimal'},body:JSON.stringify({state:'unknown',error_code:'ResponseUnknown',updated_at:new Date().toISOString()})})}
  }
  return json({attempted});
 }catch{if(notificationId&&recipient)try{await call('push_delivery_log?on_conflict=notification_id,device_key',{method:'POST',headers:{Prefer:'resolution=ignore-duplicates,return=minimal'},body:JSON.stringify({notification_id:notificationId,recipient_phone:recipient,device_key:'event',state:'failed',error_code:'InternalError'})})}catch{}return json({error:'Push operation failed'},502)}
});
