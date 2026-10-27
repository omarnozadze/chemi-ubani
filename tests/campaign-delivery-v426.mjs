const {PGlite}=await import(process.env.PGLITE_MODULE||'@electric-sql/pglite');
import fs from 'node:fs';import assert from 'node:assert/strict';
const db=new PGlite();
await db.exec(`create role anon; create role authenticated; create schema app_private; create schema auth; grant usage on schema app_private to authenticated; set check_function_bodies=off;
create function app_private.verified_phone() returns text language plpgsql as $$begin if nullif(current_setting('test.phone',true),'') is null then raise exception 'Login required' using errcode='42501';end if;return current_setting('test.phone');end$$;
create function auth.uid() returns uuid language sql as $$select null::uuid$$;
create function auth.jwt() returns jsonb language sql as $$select '{}'::jsonb$$;`);
const cols=JSON.parse(fs.readFileSync('tests/fixtures/columns-snapshot.json'));
for(const table of [...new Set(cols.map(c=>c.table_name))]){
 const cs=cols.filter(c=>c.table_name===table).map(c=>`${c.column_name} ${c.udt_name==='_text'?'text[]':c.udt_name}${c.column_name==='id'?' default gen_random_uuid()':c.udt_name==='timestamptz'?' default now()':''}`);
 await db.exec(`create table public.${table}(${cs});`);
}
await db.exec(`alter table public.direct_chat_reads add primary key(thread_id,phone);`);
const rpcs=JSON.parse(fs.readFileSync('tests/fixtures/rpc-snapshot.json'));
for(const r of rpcs)await db.exec(r.definition);
await db.exec(fs.readFileSync('supabase/verified-api-v424.sql','utf8'));
await db.exec(fs.readFileSync('supabase/app-features-v424.sql','utf8'));
await db.exec('set check_function_bodies=on;');
await db.exec(`alter table public.profiles add primary key(phone);alter table public.businesses add primary key(id);create function auth.role() returns text language sql as $$select 'authenticated'::text$$;`);
await db.exec(fs.readFileSync('supabase/notification-events.sql','utf8'));
for(const file of ['day-boundary','admin-campaigns','business-ratings'])await db.exec(fs.readFileSync('supabase/'+file+'-v4241.sql','utf8'));

await db.exec(`create role service_role;create schema storage;create table storage.buckets(id text primary key,public boolean);create table storage.objects(bucket_id text,name text);alter table storage.objects enable row level security;grant usage on schema storage to authenticated;grant select on storage.objects to authenticated;insert into storage.buckets values('chat-images',true),('daily-moments',true),('day-images',true);`);
const migration=fs.readdirSync('supabase/migrations').find(x=>x.endsWith('_reliability_v425.sql'));await db.exec(fs.readFileSync('supabase/migrations/'+migration,'utf8'));
await db.exec(`insert into profiles(phone,full_name,city,district,neighborhood,is_super_admin,admin_level) values('511111111','Admin','თბილისი','ვაკე','ბაგები',true,'super'),('522222222','Peer','თბილისი','ვაკე','ბაგები',false,'user'),('533333333','Other','თბილისი','ვაკე','ბაგები',false,'user');select set_config('test.phone','511111111',false);`);

await db.exec('alter table public.notifications add primary key(id)');
await db.exec(fs.readFileSync('supabase/migrations/20260915133957_campaign_delivery_v426.sql','utf8'));
await db.exec('set role authenticated');
const data={title:'Before',body:'Old body',category:'მნიშვნელოვანი',placement:'ცხელი ამბები',city:'თბილისი',districts:['ვაკე'],days:7};
const id=(await db.query('select public.publish_admin_campaign($1,$2)r',[data,'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'])).rows[0].r.id;
const initial=(await db.query('select public.list_admin_campaigns()r')).rows[0].r[0];assert.equal(initial.revision,1);
await db.exec('reset role');const notificationCount=(await db.query('select count(*)::int n from notifications')).rows[0].n;
await db.exec('set role authenticated');
const edit=()=>db.query('select public.edit_admin_campaign($1,1,$2,$3,$4)r',[id,'After','New body','https://example.com/new.jpg']);
assert.equal((await edit()).rows[0].r.revision,2);assert.equal((await edit()).rows[0].r.revision,2);
const stale=(await db.query('select public.edit_admin_campaign($1,1,$2,$3,null)r',[id,'Stale','Stale body'])).rows[0].r;assert.equal(stale.code,'conflict');
const hot=(await db.query('select public.list_hot_news()r')).rows[0].r[0];assert.equal(hot.title,'After');assert.equal(hot.image_url,'https://example.com/new.jpg');
const changed=(await db.query('select public.list_admin_campaigns()r')).rows[0].r[0];assert.equal(changed.id,id);assert.equal(changed.expires_at,initial.expires_at);assert.equal(changed.placement,initial.placement);
await db.exec('reset role');assert.equal((await db.query('select count(*)::int n from notifications')).rows[0].n,notificationCount);
const note=(await db.query('select id,recipient_phone from notifications limit 1')).rows[0];
await db.query("insert into push_delivery_log(notification_id,device_key,recipient_phone,state,error_code)values($1,'hashed-device',$2,'failed','InvalidCredentials')",[note.id,note.recipient_phone]);
await db.exec('set role authenticated');const logs=(await db.query('select public.admin_push_diagnostics()r')).rows[0].r;assert.equal(logs[0].recipient,'***'+note.recipient_phone.slice(-4));assert.equal(logs[0].state,'failed');assert.equal(logs[0].receipt_id,undefined);assert.equal(logs[0].device_key,undefined);assert.equal((await db.query("select public.admin_push_diagnostics('accepted')r")).rows[0].r.length,0);
await assert.rejects(()=>db.query('select * from push_delivery_log'),e=>e.code==='42501');
await db.exec("reset role;select set_config('test.phone','522222222',false);set role authenticated");await assert.rejects(()=>edit(),e=>e.code==='42501');await assert.rejects(()=>db.query('select public.admin_push_diagnostics()'),e=>e.code==='42501');
await db.exec('reset role;set role anon');await assert.rejects(()=>db.query('select public.admin_push_diagnostics()'),e=>e.code==='42501');
await db.close();console.log('PASS: same campaign ID/expiry/placement; news updated; no duplicate push; idempotent edit retry; revision conflict; admin-only diagnostics/editing; masked recipient and no tokens/receipts exposed.');
