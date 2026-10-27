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
let tested=0;
for(const r of rpcs){
 const params=r.args.split(', ').filter(Boolean);
 const actor=params.find(x=>/^(p_phone|p_viewer_phone) text$/.test(x));
 if(!actor)continue;
 const def=(await db.query(`select pg_get_functiondef(p.oid) d from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and proname=$1`,[r.proname])).rows;
 if(!def.some(x=>x.d.includes('app_private.assert_actor')))continue;
 const values=params.map(x=>{const [name,...type]=x.split(' ');return name===actor.split(' ')[0]?"'599999999'::text":'NULL::'+type.join(' ')});
 await db.exec("select set_config('test.phone','511111111',false);set role authenticated;");
 try{await db.query(`select public.${r.proname}(${values.join(',')})`);throw Error('Spoof allowed '+r.proname)}catch(e){assert.equal(e.code,'42501',r.proname+': '+e.message)}
 await db.exec('reset role;');tested++;
}
console.log('Identity mismatch rejected:',tested);
await db.exec(`select set_config('test.phone','511111111',false);insert into profiles(phone,full_name) values('511111111','A'),('522222222','B');insert into direct_chat_threads(id,user_a,user_b) values('11111111-1111-4111-8111-111111111111','511111111','522222222');`);
const args="'direct','11111111-1111-4111-8111-111111111111','hello',null,'22222222-2222-4222-8222-222222222222'";
await db.exec('set role authenticated;');
const a=(await db.query(`select public.send_chat_message_verified(${args}) r`)).rows[0].r;
const b=(await db.query(`select public.send_chat_message_verified(${args}) r`)).rows[0].r;
assert.deepEqual(a,b);assert.equal(a.ok,true);
await db.exec('reset role;');assert.equal((await db.query('select count(*)::int n from direct_chat_messages')).rows[0].n,1);
await db.exec(`insert into notifications(id,recipient_phone,kind,source_event) values('33333333-3333-4333-8333-333333333333','522222222','direct_message','direct:${a.id}');select set_config('test.phone','522222222',false);set role authenticated;`);
const route=(await db.query("select public.resolve_notification('33333333-3333-4333-8333-333333333333') r")).rows[0].r;assert.equal(route.kind,'direct');assert.equal(route.other.phone,'511111111');
await db.exec("select set_config('test.phone','533333333',false)");
await assert.rejects(()=>db.query("select public.resolve_notification('33333333-3333-4333-8333-333333333333')"),e=>e.code==='42501');
await assert.rejects(()=>db.query("select public.mark_conversation_read_v423('533333333','direct','11111111-1111-4111-8111-111111111111',now())"),e=>e.code==='42501');
console.log('Retry deduplication, notification ownership and read membership: PASS');
await db.exec(`reset role;create schema storage;create table storage.objects(bucket_id text,name text);alter table storage.objects enable row level security;grant usage on schema storage to authenticated,anon;grant insert on storage.objects to authenticated,anon;`);
await db.exec(fs.readFileSync('supabase/storage-uploads-v424.sql','utf8'));
await db.exec(`select set_config('test.phone','511111111',false);set role authenticated;insert into storage.objects values('chat-images','511111111/photo.jpg');`);
await assert.rejects(()=>db.query("insert into storage.objects values('chat-images','522222222/photo.jpg')"),e=>e.code==='42501');
await db.exec('reset role;set role anon;');
await assert.rejects(()=>db.query("insert into storage.objects values('chat-images','511111111/photo.jpg')"),e=>e.code==='42501');
console.log('Storage: own folder allowed; impersonated and anonymous uploads denied.');
await db.exec(`reset role;insert into live_chats(id,name) values('44444444-4444-4444-8444-444444444444','Test');insert into live_chat_members(chat_id,phone) values('44444444-4444-4444-8444-444444444444','511111111');insert into live_chat_messages(chat_id,sender_phone,sender_name,body,created_at) select '44444444-4444-4444-8444-444444444444','522222222','B',i::text,now()-interval '1000 seconds'+i*interval '1 second' from generate_series(1,501) i;set role authenticated;`);
const latest=(await db.query("select * from public.list_live_chat_messages('511111111','44444444-4444-4444-8444-444444444444')")).rows;assert.equal(latest.length,500);assert.equal(latest[0].body,'2');assert.equal(latest[499].body,'501');
console.log('Group history returns the latest 500 messages in chronological order.');

await db.close();
