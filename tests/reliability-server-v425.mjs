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
const pref={enabled:true,messages:false,daily_photo:true,reactions:true,friends:true,hot_news:true,services:true,other:true,quiet_enabled:true,quiet_start:1380,quiet_end:480};
await db.query('select public.set_notification_preferences($1)',[pref]);const allowed=async(kind,time)=>(await db.query('select app_private.notification_allowed($1,$2,$3) v',[pref,kind,time])).rows[0].v;
assert.equal(await allowed('direct_message','2026-09-15T08:00Z'),false);assert.equal(await allowed('daily_photo','2026-09-15T18:59Z'),true);assert.equal(await allowed('daily_photo','2026-09-15T19:00Z'),false);assert.equal(await allowed('hot_news','2026-09-16T03:59Z'),false);assert.equal(await allowed('hot_news','2026-09-16T04:00Z'),true);
await db.exec(`insert into direct_chat_threads(id,user_a,user_b) values('11111111-1111-4111-8111-111111111111','511111111','522222222');insert into direct_chat_messages(thread_id,sender_phone,body,image_url)values('11111111-1111-4111-8111-111111111111','511111111','Photo','https://example.com/storage/v1/object/public/chat-images/511111111/photo.jpg');insert into storage.objects values('chat-images','511111111/photo.jpg');`);
await db.exec("select set_config('test.phone','522222222',false);set role authenticated");assert.equal((await db.query('select * from storage.objects')).rows.length,1);await db.exec("reset role;select set_config('test.phone','533333333',false);set role authenticated");assert.equal((await db.query('select * from storage.objects')).rows.length,0);await assert.rejects(()=>db.query("select public.conversation_page('direct','11111111-1111-4111-8111-111111111111')"),e=>e.code==='42501');await assert.rejects(()=>db.query('select public.admin_operational_stats()'),e=>e.code==='42501');
await db.exec("reset role;select set_config('test.phone','511111111',false);insert into direct_chat_messages(thread_id,sender_phone,body,created_at)select '11111111-1111-4111-8111-111111111111','511111111',i::text,'2026-09-15 12:00+00'from generate_series(1,105)i;set role authenticated");const first=(await db.query("select public.conversation_page('direct','11111111-1111-4111-8111-111111111111') r")).rows[0].r;assert.equal(first.length,50);const next=(await db.query("select public.conversation_page('direct','11111111-1111-4111-8111-111111111111',$1,$2)r",[first[0].created_at,first[0].id])).rows[0].r;assert.equal(next.length,50);assert.equal(new Set([...first,...next].map(x=>x.id)).size,100);
await db.query("select public.record_app_health('rpc_failed','chat','4.25.0')");await assert.rejects(()=>db.query("select public.record_app_health('secret message','chat','4.25.0')"),/Invalid/);const stats=(await db.query('select public.admin_operational_stats() r')).rows[0].r;assert.equal(stats.users,3);assert.equal(stats.active_users,1);assert.equal(stats.errors[0].code,'rpc_failed');

// A stranger cannot gain access by inserting someone else's photo URL in their own thread.
await db.exec("reset role;insert into direct_chat_threads(id,user_a,user_b)values('33333333-3333-4333-8333-333333333333','533333333','522222222');insert into direct_chat_messages(thread_id,sender_phone,image_url)values('33333333-3333-4333-8333-333333333333','533333333','https://example.com/storage/v1/object/public/chat-images/511111111/photo.jpg');select set_config('test.phone','533333333',false);set role authenticated");
assert.equal((await db.query("select public.can_read_private_image('chat-images','511111111/photo.jpg')v")).rows[0].v,false);
// Old day photos remain available only to their owner through the private archive.
await db.exec("reset role;insert into daily_moments(phone,back_image_url,front_image_url,created_at,owner_confirmed_at)values('511111111','https://example.com/storage/v1/object/public/daily-moments/511111111/old.jpg','https://example.com/storage/v1/object/public/daily-moments/511111111/oldfront.jpg',now()-interval '2 days',now()-interval '2 days');insert into daily_photo_friends(user_phone,friend_phone)values('522222222','511111111');select set_config('test.phone','522222222',false);set role authenticated");
assert.equal((await db.query("select public.can_read_private_image('daily-moments','511111111/old.jpg')v")).rows[0].v,false);
await db.exec("reset role;select set_config('test.phone','511111111',false);set role authenticated");assert.equal((await db.query("select public.can_read_private_image('daily-moments','511111111/old.jpg')v")).rows[0].v,true);
// Publisher actions are audited and campaign counts deduplicate repeat views.
const campaign=(await db.query('select public.publish_admin_campaign($1,$2)r',[{title:'Campaign',body:'News',category:'მნიშვნელოვანი',placement:'ცხელი ამბები',city:'თბილისი',districts:['ვაკე'],days:7},'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'])).rows[0].r.id;
await db.query("select public.record_campaign_event($1,'view')",[campaign]);await db.query("select public.record_campaign_event($1,'view')",[campaign]);await db.query("select public.record_campaign_event($1,'click')",[campaign]);
const report=(await db.query('select public.admin_operational_stats()r')).rows[0].r;assert.equal(report.events[0].views,1);assert.equal(report.events[0].clicks,1);assert.equal(report.events[0].reach,1);assert.ok(report.audit.some(x=>x.action==='admin_campaigns:insert'&&x.target_ref===campaign));
assert.equal((await db.query('select public.list_hot_news()r')).rows[0].r[0].campaign_id,campaign);
await assert.rejects(()=>db.query("select public.record_push_failure('11111111-1111-4111-8111-111111111111')"),e=>e.code==='42501');
await db.exec('reset role');assert.equal((await db.query('select count(*)::int n from storage.buckets where public')).rows[0].n,0);
await db.exec('reset role;set role anon');await assert.rejects(()=>db.query('select public.get_notification_preferences()'),e=>e.code==='42501');
console.log('PASS: category + Georgia quiet boundaries; private participant-only objects; outsider denial; stable 50-row cursor; real counters; diagnostic allowlist; anonymous rejection.');await db.close();
