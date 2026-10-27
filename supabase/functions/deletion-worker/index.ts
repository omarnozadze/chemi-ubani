// No credentials in the client. All work items originate in guarded SQL transactions.
const headers={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization,apikey,content-type,x-deletion-worker','Access-Control-Allow-Methods':'POST, OPTIONS','Content-Type':'application/json'};
const url=Deno.env.get('SUPABASE_URL')!,service=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
async function call(path:string,body:unknown,method='POST',token=service){const r=await fetch(url+path,{method,signal:AbortSignal.timeout(10000),headers:{apikey:service,Authorization:'Bearer '+token,'Content-Type':'application/json'},...(body===undefined?{}:{body:JSON.stringify(body)})});const data=await r.json().catch(()=>null);if(!r.ok)throw new Error('upstream_'+r.status);return data;}
const rpc=(name:string,args:unknown={})=>call('/rest/v1/rpc/'+name,args);
export async function handler(req:Request){
 if(req.method==='OPTIONS')return new Response(null,{headers});
 if(req.method!=='POST')return new Response('{}',{status:405,headers});
 try{
  const secret=req.headers.get('x-deletion-worker');
  if(secret){if(!await rpc('deletion_worker_authorized_v436',{p_secret:secret}))return new Response('{}',{status:403,headers});}
  else{
   const token=(req.headers.get('Authorization')||'').replace(/^Bearer /i,'');
   if(!token||token===service)return new Response('{}',{status:401,headers});
   await call('/auth/v1/user',undefined,'GET',token);
   // A valid user may wake the queue, never specify a path, phone, or Auth id.
  }
  if(!await rpc('deletion_worker_claim_v436'))return new Response(JSON.stringify({ok:true,queued:true}),{headers});
  let files=0,accounts=0,failed=0;
  const work=await rpc('deletion_work_v436');
  const deadline=Date.now()+40000;
  for(const f of work.files){if(Date.now()>deadline)break;try{
   if(await rpc('deletion_file_action_v436',{p_id:f.id})==='delete')await call('/storage/v1/object/'+encodeURIComponent(f.bucket),{prefixes:[f.path]},'DELETE');
   await rpc('deletion_file_done_v436',{p_id:f.id,p_ok:true});files++;
  }catch{failed++;await rpc('deletion_file_done_v436',{p_id:f.id,p_ok:false}).catch(()=>{});}}
  // Re-query after Storage cleanup; Auth deletion comes LAST. Failures remain queued for cron.
  const ready=await rpc('deletion_work_v436');
  for(const a of ready.accounts){if(Date.now()>deadline)break;try{
   try{await call('/auth/v1/admin/users/'+encodeURIComponent(a.user_id),{should_soft_delete:false},'DELETE');}catch(e){if(!(e instanceof Error&&e.message==='upstream_404'))throw e;}
   await rpc('deletion_account_done_v436',{p_id:a.id});accounts++;
  }catch{failed++;}}
  return new Response(JSON.stringify({ok:failed===0,files,accounts,retrying:failed>0}),{headers});
 }catch{return new Response(JSON.stringify({ok:false,message:'Cleanup will retry.'}),{status:503,headers});}
}
Deno.serve(handler);
