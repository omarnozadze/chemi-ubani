import fs from 'node:fs';import assert from 'node:assert/strict';import vm from 'node:vm';import {stripTypeScriptTypes}from'node:module';import{webcrypto}from'node:crypto';
let handler,logs=[],sent=0,allowed=true,secret=true,superadmin=true,providerError=false,receiptError=false,calls=[];
const response=data=>Response.json(data),token='ExponentPushToken[test]';
vm.runInNewContext(stripTypeScriptTypes(fs.readFileSync('supabase/functions/activity-push/index.ts','utf8')),{Response,AbortSignal,TextEncoder,crypto:webcrypto,fetch:async(url,init={})=>{
 calls.push({url,init});const body=init.body?JSON.parse(init.body):{};
 if(url.includes('get_verified_profile'))return response({is_super_admin:superadmin});
 if(url.includes('verify_activity_push_secret'))return response(secret);
 if(url.includes('push_delivery_allowed'))return response(allowed);
 if(url.includes('/notifications?'))return response([{recipient_phone:'511111111'}]);
 if(url.includes('push_devices?'))return init.method==='DELETE'?new Response(null,{status:204}):response([{token}]);
 if(url.includes('push_delivery_log')){
  const u=new URL(url);if(init.method==='POST'){if(logs.some(x=>x.device_key===body.device_key&&x.notification_id===body.notification_id))return response([]);const row={...body,id:String(logs.length+1)};logs.push(row);return response([row])}
  if(init.method==='PATCH'){if(u.searchParams.has('id')){const row=logs.find(x=>'eq.'+x.id===u.searchParams.get('id'));if(row&&(!u.searchParams.has('state')||'eq.'+row.state===u.searchParams.get('state')))Object.assign(row,body)}return new Response(null,{status:204})}
  if(init.method==='DELETE')return new Response(null,{status:204});return response(logs.filter(x=>x.state==='accepted'));
 }
 if(url.includes('/push/send')){sent++;return response({data:[providerError?{status:'error',details:{error:'InvalidCredentials'}}:{status:'ok',id:'ticket-1'}]})}
 if(url.includes('/push/getReceipts'))return response({data:{'ticket-1':receiptError?{status:'error',details:{error:'DeviceNotRegistered'}}:{status:'ok'}}});
 throw Error('Unexpected request '+url);
},Deno:{env:{get:n=>n==='SUPABASE_URL'?'https://test.supabase.co':'key'},serve:fn=>handler=fn}});
const webhook=()=>new Request('https://test/function',{method:'POST',headers:{'x-webhook-secret':'secret'},body:JSON.stringify({type:'INSERT',table:'notifications',record:{id:'11111111-1111-4111-8111-111111111111',recipient_phone:'spoofed'}})});
const check=()=>new Request('https://test/function',{method:'POST',headers:{Authorization:'Bearer session'},body:JSON.stringify({action:'check_receipts'})});
assert.equal((await handler(new Request('https://test/function',{method:'POST'}))).status,401);assert.equal(sent,0);
secret=false;assert.equal((await handler(webhook())).status,401);secret=true;allowed=false;await handler(webhook());assert.equal(logs[0].state,'suppressed');assert.equal(sent,0);
logs=[];allowed=true;await handler(webhook());assert.equal(logs[0].state,'accepted');assert.equal(logs[0].receipt_id,'ticket-1');assert.equal(logs[0].recipient_phone,'511111111');assert.equal(JSON.stringify(logs).includes(token),false);assert.equal(logs[0].device_key.length,64);await handler(webhook());assert.equal(sent,1,'duplicate webhook cannot send the same device twice');
superadmin=false;const before=calls.length;assert.equal((await handler(check())).status,403);assert.equal(calls.length,before+1);superadmin=true;await handler(check());assert.equal(logs[0].state,'provider_accepted');
logs=[];providerError=true;await handler(webhook());assert.equal(logs[0].state,'failed');assert.equal(logs[0].error_code,'InvalidCredentials');
logs=[];providerError=false;receiptError=true;await handler(webhook());await handler(check());assert.equal(logs[0].error_code,'DeviceNotRegistered');assert.ok(calls.some(x=>x.url.includes('push_devices?')&&x.init.method==='DELETE'));
console.log('PASS: secret and live-admin gates; suppressed status; hashed token log; ticket IDs; duplicate webhook protection; receipt success/error; invalid token cleanup.');
