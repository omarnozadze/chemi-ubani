-- v436: owner deletion and per-person conversation clearing. No client-supplied owner.
create table app_private.conversation_clears_v436(phone text not null references public.profiles(phone) on delete cascade,kind text not null check(kind in('direct','group')),id uuid not null,cleared_at timestamptz not null,primary key(phone,kind,id));
alter table app_private.conversation_clears_v436 enable row level security;
revoke all on app_private.conversation_clears_v436 from public,anon,authenticated;
create table app_private.file_deletions_v436(id bigint generated always as identity primary key,bucket text not null,path text not null,object_id uuid,created_at timestamptz not null default now(),attempts integer not null default 0,unique(bucket,path));
alter table app_private.file_deletions_v436 enable row level security;
revoke all on app_private.file_deletions_v436 from public,anon,authenticated;
-- Queue only existing objects owned by the row's owner. A forged URL cannot delete another user's file.
create function app_private.queue_deleted_files_v436()returns trigger language plpgsql security definer set search_path=''as $$
declare d jsonb:=to_jsonb(old);who text;uid uuid;begin
 who:=coalesce(d->>'author_phone',d->>'owner_phone',d->>'sender_phone',d->>'phone');
 select auth_user_id into uid from public.profiles where phone=who;
 insert into app_private.file_deletions_v436(bucket,path,object_id)
 select o.bucket_id,o.name,o.id from storage.objects o
 where (split_part(o.name,'/',1)=who or (uid is not null and(o.owner_id=uid::text or split_part(o.name,'/',1)=uid::text)))
 and (exists(select 1 from jsonb_each_text(d)f where f.key in('image_url','photo_url','back_image_url','front_image_url','avatar_url')and position('/'||o.bucket_id||'/'||o.name in f.value)>0)
 or (o.bucket_id='chat-files' and d->'attachment'->>'path'=o.name))
 on conflict(bucket,path)do nothing;return old;end$$;
revoke all on function app_private.queue_deleted_files_v436()from public,anon,authenticated;
do $$declare t text;begin foreach t in array array['posts','daily_moments','my_day_posts','specialist_announcements','marketplace_listings','live_chats','live_chat_messages','direct_chat_messages']loop execute format('create trigger queue_deleted_files_v436 before delete on public.%I for each row execute function app_private.queue_deleted_files_v436()',t);end loop;end$$;
create function app_private.owned_items_v436(p_kind text,p_before timestamptz default null,p_before_id uuid default null)returns jsonb language plpgsql security definer set search_path=''as $$
declare actor text:=app_private.verified_phone();r jsonb;begin
 select coalesce(jsonb_agg(to_jsonb(x)order by x.created_at desc,x.id desc),'[]')into r from(
 select * from(
 select 'post'::text kind,id,coalesce(left(content,100),'პოსტი')title,created_at from public.posts where p_kind='post'and author_phone=actor
 union all select 'daily',id,coalesce(nullif(caption,''),'დღის ფოტო'),created_at from public.daily_moments where p_kind='daily'and phone=actor
 union all select 'myday',id,coalesce(nullif(caption,''),'დღის ფოტო'),created_at from public.my_day_posts where p_kind='daily'and owner_phone=actor
 union all select 'service',id,title,created_at from public.specialist_announcements where p_kind='service'and owner_phone=actor
 union all select 'group',c.id,c.name,c.created_at from public.live_chats c where p_kind='group'and(c.owner_phone=actor or exists(select 1 from public.live_chat_members m where m.chat_id=c.id and m.phone=actor and m.role in('owner','admin')))
 )q where p_before is null or(created_at,id)<(p_before,p_before_id)order by created_at desc,id desc limit 30)x;
 return r;end$$;
create function app_private.delete_owned_v436(p_kind text,p_id uuid)returns jsonb language plpgsql security definer set search_path=''as $$
declare actor text:=app_private.verified_phone();n integer;begin
 if p_kind='post'then delete from public.posts where id=p_id and author_phone=actor;
 elsif p_kind='daily'then delete from public.daily_moments where id=p_id and phone=actor;
 elsif p_kind='myday'then delete from public.my_day_posts where id=p_id and owner_phone=actor;
 elsif p_kind='service'then delete from public.specialist_announcements where id=p_id and owner_phone=actor;
 elsif p_kind='group'then
 perform 1 from public.live_chats where id=p_id for update;
 delete from public.live_chats c where c.id=p_id and(c.owner_phone=actor or exists(select 1 from public.live_chat_members m where m.chat_id=c.id and m.phone=actor and m.role in('owner','admin')));
 else raise exception 'Invalid item';end if;
 get diagnostics n=row_count;
 if n=0 then raise exception 'ჩანაწერი წაიშალა ან მისი წაშლის უფლება არ გაქვს.'using errcode='42501';end if;
 if p_kind='group'then delete from public.chat_favorites where conversation_type='group'and conversation_id=p_id;delete from app_private.conversation_clears_v436 where kind='group'and id=p_id;delete from app_private.message_requests where payload->>'kind'='group'and payload->>'id'=p_id::text;end if;
 return jsonb_build_object('ok',true);end$$;
create function app_private.clear_conversation_v436(p_kind text,p_id uuid)returns jsonb language plpgsql security definer set search_path=''as $$
declare actor text:=app_private.verified_phone();cutoff timestamptz:=clock_timestamp();begin
 perform app_private.assert_conversation(p_kind,p_id);
 insert into app_private.conversation_clears_v436 values(actor,p_kind,p_id,cutoff)on conflict(phone,kind,id)do update set cleared_at=excluded.cleared_at;
 delete from public.chat_favorites where phone=actor and conversation_type=p_kind and conversation_id=p_id;
 if p_kind='direct'then insert into public.direct_chat_reads(thread_id,phone,last_read_at)values(p_id,actor,cutoff)on conflict(thread_id,phone)do update set last_read_at=excluded.last_read_at;
 else update public.live_chat_members set last_read_at=cutoff where chat_id=p_id and phone=actor;end if;
 return jsonb_build_object('ok',true,'cleared_at',cutoff);end$$;
create function public.owned_items_v436(p_kind text,p_before timestamptz default null,p_before_id uuid default null)returns jsonb language sql security invoker set search_path=''as $$select app_private.owned_items_v436(p_kind,p_before,p_before_id)$$;
revoke all on function public.owned_items_v436(text,timestamptz,uuid),app_private.owned_items_v436(text,timestamptz,uuid)from public,anon;
grant execute on function public.owned_items_v436(text,timestamptz,uuid),app_private.owned_items_v436(text,timestamptz,uuid)to authenticated;
create function public.delete_owned_v436(p_kind text,p_id uuid)returns jsonb language sql security invoker set search_path=''as $$select app_private.delete_owned_v436(p_kind,p_id)$$;
revoke all on function public.delete_owned_v436(text,uuid),app_private.delete_owned_v436(text,uuid)from public,anon;
grant execute on function public.delete_owned_v436(text,uuid),app_private.delete_owned_v436(text,uuid)to authenticated;
create function public.clear_conversation_v436(p_kind text,p_id uuid)returns jsonb language sql security invoker set search_path=''as $$select app_private.clear_conversation_v436(p_kind,p_id)$$;
revoke all on function public.clear_conversation_v436(text,uuid),app_private.clear_conversation_v436(text,uuid)from public,anon;
grant execute on function public.clear_conversation_v436(text,uuid),app_private.clear_conversation_v436(text,uuid)to authenticated;
create or replace function app_private.chat_page_data(p_kind text,p_id uuid,p_query text default null,p_before timestamptz default null,p_before_id uuid default null,p_message uuid default null,p_limit integer default 50)returns jsonb language plpgsql security definer set search_path='' as $$declare result jsonb;cutoff timestamptz;begin
 perform app_private.assert_conversation(p_kind,p_id);
 select cleared_at into cutoff from app_private.conversation_clears_v436 where phone=app_private.verified_phone()and kind=p_kind and id=p_id;
 if p_limit<1 or p_limit>50 then raise exception 'Invalid page size';end if;
 if p_kind='direct'then
 select coalesce(jsonb_agg(x.data order by x.created_at,x.id),'[]')into result from(
 select m.id,m.created_at,to_jsonb(m)||jsonb_build_object('sender_name',p.full_name,'reply',case when r.id is null then null else jsonb_build_object('id',r.id,'sender_name',rp.full_name,'body',left(r.body,300),'has_image',r.image_url is not null)end)data
 from(select * from public.direct_chat_messages where thread_id=p_id and(cutoff is null or created_at>cutoff)and(p_message is null or id=p_message)and(p_before is null or(created_at,id)<(p_before,p_before_id))and(p_query is null or position(lower(p_query)in lower(coalesce(body,'')))>0)order by created_at desc,id desc limit p_limit)m
 left join public.profiles p on p.phone=m.sender_phone left join public.direct_chat_messages r on r.id=m.reply_to and r.thread_id=m.thread_id and(cutoff is null or r.created_at>cutoff) left join public.profiles rp on rp.phone=r.sender_phone)x;
 else
 select coalesce(jsonb_agg(x.data order by x.created_at,x.id),'[]')into result from(
 select m.id,m.created_at,to_jsonb(m)||jsonb_build_object('sender_name',p.full_name,'reply',case when r.id is null then null else jsonb_build_object('id',r.id,'sender_name',rp.full_name,'body',left(r.body,300),'has_image',r.image_url is not null)end)data
 from(select * from public.live_chat_messages where chat_id=p_id and(cutoff is null or created_at>cutoff)and(p_message is null or id=p_message)and(p_before is null or(created_at,id)<(p_before,p_before_id))and(p_query is null or position(lower(p_query)in lower(coalesce(body,'')))>0)order by created_at desc,id desc limit p_limit)m
 left join public.profiles p on p.phone=m.sender_phone left join public.live_chat_messages r on r.id=m.reply_to and r.chat_id=m.chat_id and(cutoff is null or r.created_at>cutoff) left join public.profiles rp on rp.phone=r.sender_phone)x;
 end if;return result;end$$;
CREATE OR REPLACE FUNCTION app_private.legacy_list_direct_chats(p_phone text)
 RETURNS TABLE(id uuid, other_phone text, other_name text, other_avatar_url text, other_district text, last_message text, last_message_at timestamp with time zone, unread_count bigint, is_favorite boolean)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with me as(select regexp_replace(coalesce(p_phone,''),'\D','','g') phone)
  select t.id,p.phone,p.full_name,p.avatar_url,p.district,
    (select coalesce(nullif(m.body,''),'📷 ფოტო') from public.direct_chat_messages m where m.thread_id=t.id order by m.created_at desc limit 1),
    (select m.created_at from public.direct_chat_messages m where m.thread_id=t.id order by m.created_at desc limit 1),
    (select count(*) from public.direct_chat_messages m
      where m.thread_id=t.id and m.sender_phone<>me.phone
      and m.created_at>coalesce((select r.last_read_at from public.direct_chat_reads r where r.thread_id=t.id and r.phone=me.phone),t.created_at)),
    exists(select 1 from public.chat_favorites f where f.phone=me.phone and f.conversation_type='direct' and f.conversation_id=t.id)
  from public.direct_chat_threads t cross join me
  join public.profiles p on p.phone=case when t.user_a=me.phone then t.user_b else t.user_a end
  where not exists(select 1 from app_private.conversation_clears_v436 z where z.phone=me.phone and z.kind='direct'and z.id=t.id and not exists(select 1 from public.direct_chat_messages fresh where fresh.thread_id=t.id and fresh.created_at>z.cleared_at))and me.phone in(t.user_a,t.user_b) and not public.is_user_blocked(me.phone,p.phone)
  order by exists(select 1 from public.chat_favorites f where f.phone=me.phone and f.conversation_type='direct' and f.conversation_id=t.id) desc,
    coalesce((select max(m.created_at) from public.direct_chat_messages m where m.thread_id=t.id),t.created_at) desc;
$function$
;

CREATE OR REPLACE FUNCTION app_private.legacy_list_live_chats_for_phone(p_phone text)
 RETURNS TABLE(id uuid, name text, description text, photo_url text, owner_phone text, my_role text, member_count bigint, last_message text, last_message_at timestamp with time zone, unread_count bigint, is_favorite boolean)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select c.id,c.name,c.description,c.photo_url,c.owner_phone,m.role,
    (select count(*) from public.live_chat_members cm where cm.chat_id=c.id),
    (select coalesce(nullif(lm.body,''),'📷 ფოტო') from public.live_chat_messages lm where lm.chat_id=c.id order by lm.created_at desc limit 1),
    (select lm.created_at from public.live_chat_messages lm where lm.chat_id=c.id order by lm.created_at desc limit 1),
    (select count(*) from public.live_chat_messages x where x.chat_id=c.id and x.sender_phone<>m.phone and x.created_at>m.last_read_at),
    exists(select 1 from public.chat_favorites f where f.phone=m.phone and f.conversation_type='group' and f.conversation_id=c.id)
  from public.live_chats c join public.live_chat_members m on m.chat_id=c.id
  where not exists(select 1 from app_private.conversation_clears_v436 z where z.phone=m.phone and z.kind='group'and z.id=c.id and not exists(select 1 from public.live_chat_messages fresh where fresh.chat_id=c.id and fresh.created_at>z.cleared_at))and m.phone=regexp_replace(coalesce(p_phone,''),'\D','','g')
  order by exists(select 1 from public.chat_favorites f where f.phone=m.phone and f.conversation_type='group' and f.conversation_id=c.id) desc,
    coalesce((select max(x.created_at) from public.live_chat_messages x where x.chat_id=c.id),c.created_at) desc;
$function$
;


notify pgrst,'reload schema';

CREATE OR REPLACE FUNCTION app_private.legacy_list_direct_messages(p_phone text, p_thread_id uuid)
 RETURNS TABLE(id uuid, thread_id uuid, sender_phone text, sender_name text, body text, image_url text, created_at timestamp with time zone)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with me as(select regexp_replace(coalesce(p_phone,''),'\D','','g') phone)
  select m.id,m.thread_id,m.sender_phone,p.full_name,m.body,m.image_url,m.created_at
  from public.direct_chat_messages m join public.direct_chat_threads t on t.id=m.thread_id
  join public.profiles p on p.phone=m.sender_phone cross join me
  where not exists(select 1 from app_private.conversation_clears_v436 z where z.phone=me.phone and z.kind='direct'and z.id=p_thread_id and m.created_at<=z.cleared_at)and m.thread_id=p_thread_id and me.phone in(t.user_a,t.user_b)
  order by m.created_at;
$function$
;


CREATE OR REPLACE FUNCTION app_private.legacy_list_direct_messages_between(p_phone text, p_target_phone text)
 RETURNS TABLE(id uuid, sender_phone text, recipient_phone text, sender_name text, sender_avatar text, body text, created_at timestamp with time zone)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
 with x as (select regexp_replace(coalesce(p_phone,''),'\D','','g') a, regexp_replace(coalesce(p_target_phone,''),'\D','','g') b)
 select d.id,d.sender_phone,d.recipient_phone,p.full_name,p.avatar_url,d.body,d.created_at
 from public.direct_messages d join public.profiles p on p.phone=d.sender_phone,x
 where ((d.sender_phone=x.a and d.recipient_phone=x.b)or(d.sender_phone=x.b and d.recipient_phone=x.a))and not exists(select 1 from app_private.conversation_clears_v436 z join public.direct_chat_threads t on t.id=z.id where z.phone=x.a and z.kind='direct'and x.a in(t.user_a,t.user_b)and x.b in(t.user_a,t.user_b)and d.created_at<=z.cleared_at)
 order by d.created_at asc limit 500;
$function$
;


CREATE OR REPLACE FUNCTION app_private.legacy_list_live_chat_messages(p_phone text, p_chat_id uuid)
 RETURNS TABLE(id uuid, chat_id uuid, sender_phone text, sender_name text, body text, image_url text, created_at timestamp with time zone)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
select * from (select m.id,m.chat_id,m.sender_phone,m.sender_name,m.body,m.image_url,m.created_at
  from public.live_chat_messages m
  where not exists(select 1 from app_private.conversation_clears_v436 z where z.phone=app_private.verified_phone()and z.kind='group'and z.id=p_chat_id and m.created_at<=z.cleared_at)and m.chat_id=p_chat_id
    and exists(
      select 1 from public.live_chat_members cm
      where cm.chat_id=p_chat_id and cm.phone=regexp_replace(coalesce(p_phone,''),'\D','','g')
    )
  order by m.created_at desc limit 500) recent order by created_at asc;
$function$
;


CREATE OR REPLACE FUNCTION app_private.legacy_list_live_chat_messages_v420(p_phone text, p_chat_id uuid)
 RETURNS TABLE(id uuid, sender_phone text, sender_name text, sender_avatar text, body text, image_url text, created_at timestamp with time zone)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
select * from (select m.id,m.sender_phone,m.sender_name,p.avatar_url,m.body,m.image_url,m.created_at
 from public.live_chat_messages m join public.profiles p on p.phone=m.sender_phone
 where not exists(select 1 from app_private.conversation_clears_v436 z where z.phone=app_private.verified_phone()and z.kind='group'and z.id=p_chat_id and m.created_at<=z.cleared_at)and m.chat_id=p_chat_id and exists(select 1 from public.live_chat_members me where me.chat_id=p_chat_id and me.phone=regexp_replace(coalesce(p_phone,''),'\D','','g'))
 order by m.created_at desc limit 500) recent order by created_at asc;
$function$
;

