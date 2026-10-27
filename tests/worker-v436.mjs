import fs from'node:fs';import assert from'node:assert/strict';import vm from'node:vm';import{stripTypeScriptTypes}from'node:module';
const source=stripTypeScriptTypes(fs.readFileSync('supabase/functions/deletion-worker/index.ts','utf8')).replace('export async function handler','async function handler');let requests=[],claimed=true,badFile=false,validSecret=false;
const context=vm.createContext({Request,Response,AbortSignal,Date,Error,JSON,encodeURIComponent,Deno:{env:{get:n=>n==='SUPABASE_URL'?'https://supabase.test':'SERVER_KEY'},serve:h=>context.handler=h},fetch:async(url,init)=>{const path=new URL(url).pathname,body=init.body?JSON.parse(init.body):null;requests.push({path,body});let data=true,status=200;
if(path.endsWith('authorized_v436'))data=validSecret;
else if(path.endsWith('claim_v436'))data=claimed;
else if(path==='/auth/v1/user'){if(init.headers.Authorization==='Bearer invalid')status=401;else data={id:'user'}}
else if(path.endsWith('work_v436'))data={files:[{id:1,bucket:'post-images',path:'owner/one.jpg'}],accounts:[{id:'job',user_id:'user-to-delete'}]};
else if(path.endsWith('action_v436'))data='delete';
else if(path.startsWith('/storage/')&&badFile)status=503;
else if(path.startsWith('/auth/v1/admin/'))status=404;
return new Response(JSON.stringify(data),{status});}});vm.runInContext(source,context);
const invoke=(token='user',body={user_id:'victim'},headers={})=>context.handler(new Request('https://edge.test',{method:'POST',headers:{Authorization:'Bearer '+token,...headers},body:JSON.stringify(body)}));
await invoke('invalid');assert.ok(!requests.some(x=>x.path.includes('work_v436')));requests=[];
const secretFail=await invoke('user',{}, {'x-deletion-worker':'wrong'});assert.equal(secretFail.status,403);assert.ok(!requests.some(x=>x.path.startsWith('/storage/')));requests=[];
claimed=false;await invoke();assert.ok(!requests.some(x=>x.path.includes('work_v436')));requests=[];claimed=true;badFile=true;await invoke();assert.ok(requests.some(x=>x.path.endsWith('file_done_v436')&&x.body.p_ok===false));requests=[];badFile=false;
await invoke();const remove=requests.find(x=>x.path.startsWith('/storage/'));assert.deepEqual(remove.body,{prefixes:['owner/one.jpg']});assert.ok(requests.some(x=>x.path==='/auth/v1/admin/users/user-to-delete'));assert.ok(!requests.some(x=>x.path.includes('victim')));assert.ok(requests.some(x=>x.path.endsWith('account_done_v436')),'404 Auth deletion is idempotent');
assert.ok(requests.findIndex(x=>x.path.startsWith('/storage/'))<requests.findIndex(x=>x.path.startsWith('/auth/v1/admin/')));console.log('PASS worker auth, secret rejection, bounded global lease, queued-only paths/IDs, Storage failure retry, Storage before Auth, idempotent Auth 404.');
