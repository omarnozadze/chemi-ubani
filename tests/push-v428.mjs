import fs from 'node:fs';import assert from 'node:assert/strict';import vm from 'node:vm';import {stripTypeScriptTypes}from'node:module';import{webcrypto}from'node:crypto';
let handler,sent=0,secret=true,superadmin=true,mode='ok',started=true,results=[],claimed=[],receiptCalls=0;
const token='ExponentPushToken[test]',job={id:'job1',lease_id:'lease1',notification_id:'note1',token};
vm.runInNewContext(stripTypeScriptTypes(fs.readFileSync('supabase/functions/activity-push/index.ts','utf8')),{Response,AbortSignal,TextEncoder,crypto:webcrypto,fetch:async(url,init={})=>{
 const body=init.body?JSON.parse(init.body):{};
 if(url.includes('get_verified_profile'))return Response.json({is_super_admin:superadmin});
 if(url.includes('verify_activity_push_secret'))return Response.json(secret);
 if(url.includes('claim_push_batch')){const r=claimed;claimed=[];return Response.json(r)}
 if(url.includes('start_push_batch'))return Response.json(started?body.p_jobs.map(j=>j.id):[]);
 if(url.includes('finish_push_batch')){results=body.p_results;return Response.json(results.length)}
 if(url.includes('push_delivery_log')){receiptCalls++;return init.method?new Response(null,{status:204}):Response.json([])}
 if(url.includes('/push/send')){sent++;assert.equal(body[0].data.notificationId,'note1');assert.ok(!body[0].body.includes('test'));if(mode==='network')throw Error();if(mode==='429')return new Response('',{status:429});if(mode==='500')return new Response('',{status:500});return Response.json({data:[mode==='invalid'?{status:'error',details:{error:'InvalidCredentials'}}:{status:'ok',id:'ticket1'}]})}
 throw Error('Unexpected request '+url);
},Deno:{env:{get:n=>n==='SUPABASE_URL'?'https://test.supabase.co':'key'},serve:fn=>handler=fn}});
const req=(action='drain',headers={'x-webhook-secret':'secret'})=>new Request('https://test/function',{method:'POST',headers,body:JSON.stringify({action})});
assert.equal((await handler(req('drain',{}))).status,401);
secret=false;assert.equal((await handler(req())).status,401);secret=true;
for(const [m,state]of [['ok','accepted'],['429','retry'],['network','unknown'],['500','unknown'],['invalid','failed']]){mode=m;claimed=[job];assert.equal((await handler(req())).status,200);assert.equal(results[0].state,state);assert.equal(results[0].lease_id,'lease1');assert.equal(JSON.stringify(results).includes(token),false)}
const before=sent;await handler(req());assert.equal(sent,before);
started=false;claimed=[job];await handler(req());assert.equal(sent,before);
superadmin=false;assert.equal((await handler(req('check_receipts',{Authorization:'Bearer session'}))).status,403);superadmin=true;assert.equal((await handler(req('check_receipts',{Authorization:'Bearer session'}))).status,200);assert.ok(receiptCalls>0);
assert.equal((await handler(req('check_receipts'))).status,200);
console.log('PASS worker/admin authentication, tickets, 429 retry, ambiguous response quarantine, no start/no send, no tokens in diagnostics, receipt access');
