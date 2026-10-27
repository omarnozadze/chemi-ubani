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

await db.exec(`create schema extensions;create function extensions.digest(text,text)returns bytea language sql as $$select decode(md5($1),'hex')$$;alter table push_devices add primary key(token);`);
await db.exec(fs.readFileSync('supabase/reliability-v428.sql','utf8'));

await db.exec('alter table direct_chat_messages add primary key(id);alter table live_chat_messages add primary key(id);alter table live_chat_members add primary key(chat_id,phone)');
await db.exec(fs.readFileSync('supabase/conversations-v429.sql','utf8'));
const thread='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',other='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',group='cccccccc-cccc-4ccc-8ccc-cccccccccccc';
await db.query("insert into direct_chat_threads(id,user_a,user_b)values($1,'511111111','522222222'),($2,'511111111','533333333')",[thread,other]);
await db.query("insert into live_chats(id,name)values($1,'test');",[group]);await db.query("insert into live_chat_members(chat_id,phone)values($1,'511111111'),($1,'522222222')",[group]);
const target=(await db.query("insert into direct_chat_messages(thread_id,sender_phone,body)values($1,'522222222','original searchable')returning id",[thread])).rows[0].id;
const foreign=(await db.query("insert into direct_chat_messages(thread_id,sender_phone,body)values($1,'533333333','private other')returning id",[other])).rows[0].id;
const client='dddddddd-dddd-4ddd-8ddd-dddddddddddd';
await db.exec('set role authenticated');
const reply=()=>db.query("select send_chat_message_v429('direct',$1,'answer',null,$2,$3)r",[thread,client,target]);
const sent=(await reply()).rows[0].r;assert.equal(sent.ok,true);assert.equal((await reply()).rows[0].r.id,sent.id);
await assert.rejects(()=>db.query("select send_chat_message_v429('direct',$1,'different',null,$2,$3)",[thread,client,target]));
await assert.rejects(()=>db.query("select send_chat_message_v429('direct',$1,'answer',null,gen_random_uuid(),$2)",[thread,foreign]));
const page=(await db.query("select conversation_page('direct',$1)r",[thread])).rows[0].r;const row=page.find(m=>m.id===sent.id);assert.equal(row.reply.body,'original searchable');assert.equal(row.is_reply,true);
assert.equal((await db.query("select search_conversation('direct',$1,'searchable')r",[thread])).rows[0].r.length,1);
assert.equal((await db.query("select conversation_target('direct',$1,$2)r",[thread,target])).rows[0].r.id,target);
assert.equal((await db.query("select conversation_target('direct',$1,$2)r",[thread,foreign])).rows[0].r,null);
await db.exec("reset role;select set_config('test.phone','533333333',false);set role authenticated");
await assert.rejects(()=>db.query("select conversation_target('direct',$1,$2)",[thread,target]),e=>e.code==='42501');
await assert.rejects(()=>db.query("select search_conversation('group',$1,'answer')",[group]),e=>e.code==='42501');
await db.exec("reset role;select set_config('test.phone','511111111',false)");
await db.query('delete from direct_chat_messages where id=$1',[target]);const after=(await db.query("select conversation_target('direct',$1,$2)r",[thread,sent.id])).rows[0].r;assert.equal(after.reply,null);assert.equal(after.is_reply,true);assert.equal((await reply()).rows[0].r.id,sent.id,'retry after source deletion still deduplicates');
const gtarget=(await db.query("insert into live_chat_messages(chat_id,sender_phone,sender_name,body)values($1,'522222222','Peer','group original')returning id",[group])).rows[0].id;
assert.equal((await db.query("select send_chat_message_v429('group',$1,'group answer',null,gen_random_uuid(),$2)r",[group,gtarget])).rows[0].r.ok,true);
// Old post beyond page one resolves directly, but blocked/outside-district users cannot read it.
const post=(await db.query("insert into posts(author_phone,author_name,district,content,created_at)values('511111111','Admin','ვაკე','old post','2020-01-01')returning id")).rows[0].id;
await db.exec("select set_config('test.phone','522222222',false);set role authenticated");assert.equal((await db.query('select post_target($1)r',[post])).rows[0].r.id,post);
await db.exec("reset role;insert into user_blocks(blocker_phone,blocked_phone)values('522222222','511111111');set role authenticated");assert.equal((await db.query('select post_target($1)r',[post])).rows[0].r,null);
await assert.rejects(()=>db.query("select conversation_page('direct',$1)",[thread]),e=>e.code==='42501');

await db.exec("reset role;delete from user_blocks;select set_config('test.phone','522222222',false)");
// Exact photo lookup is independent of the old 100-photo feed limit and rejects expired data.
const photo=(await db.query("insert into my_day_posts(owner_phone,created_at,back_image_url)values('522222222',now(),'https://example.test/photo')returning id")).rows[0].id;
const visible=(await db.query("select app_private.daily_visible_at(now(),now()) v")).rows[0].v;
assert.equal((await db.query('select daily_target($1)r',[photo])).rows[0].r?.id||null,visible?photo:null);
await db.query("update my_day_posts set created_at='2020-01-01'where id=$1",[photo]);assert.equal((await db.query('select daily_target($1)r',[photo])).rows[0].r,null);
await db.exec("select set_config('test.phone','511111111',false)");
await db.query("insert into direct_chat_messages(thread_id,sender_phone,body,created_at)select $1,'511111111','cursor keyword',now()from generate_series(1,31)",[thread]);
const first=(await db.query("select search_conversation('direct',$1,'cursor keyword')r",[thread])).rows[0].r;assert.equal(first.length,25);const last=first.at(-1);
const second=(await db.query("select search_conversation('direct',$1,'cursor keyword',$2,$3)r",[thread,last.created_at,last.id])).rows[0].r;assert.equal(second.length,6);assert.equal(new Set([...first,...second].map(m=>m.id)).size,31);
await db.exec('reset role;set role anon');await assert.rejects(()=>db.query('select post_target($1)',[post]),e=>e.code==='42501');await assert.rejects(()=>db.query("select search_conversation('direct',$1,'answer')",[thread]),e=>e.code==='42501');
await db.close();console.log('PASS reply dedup/payload identity, same-chat guard, target/search membership, deleted-source fallback, group reply, old post/block scope and anonymous denial');
