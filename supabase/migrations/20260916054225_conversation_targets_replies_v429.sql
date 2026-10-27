-- Additive APIs, private guards, and backwards-compatible message rows.
alter table public.direct_chat_messages add column reply_to uuid references public.direct_chat_messages(id)on delete set null,add column is_reply boolean not null default false;
alter table public.live_chat_messages add column reply_to uuid references public.live_chat_messages(id)on delete set null,add column is_reply boolean not null default false;
create index direct_reply_lookup on public.direct_chat_messages(reply_to)where reply_to is not null;
create index group_reply_lookup on public.live_chat_messages(reply_to)where reply_to is not null;
create or replace function app_private.assert_conversation(p_kind text,p_id uuid)returns void language plpgsql security definer set search_path='' as $$
declare actor text:=app_private.verified_phone();begin
 if p_kind='direct'then
 if not exists(select 1 from public.direct_chat_threads t where t.id=p_id and actor in(t.user_a,t.user_b)and not public.is_user_blocked(t.user_a,t.user_b))then raise exception 'Conversation unavailable'using errcode='42501';end if;
 elsif p_kind='group'then
 if not exists(select 1 from public.live_chat_members where chat_id=p_id and phone=actor)then raise exception 'Conversation unavailable'using errcode='42501';end if;
 else raise exception 'Invalid conversation';end if;end$$;
revoke all on function app_private.assert_conversation(text,uuid)from public,anon,authenticated;

create or replace function app_private.send_chat_message_v429(p_kind text,p_id uuid,p_body text,p_image_url text,p_client_id uuid,p_reply_to uuid)returns jsonb language plpgsql security definer set search_path='' as $$
declare actor text:=app_private.verified_phone();request jsonb:=jsonb_build_object('kind',p_kind,'id',p_id,'body',p_body,'image',p_image_url,'reply_to',p_reply_to);saved app_private.message_requests%rowtype;response jsonb;begin
 perform app_private.assert_conversation(p_kind,p_id);
 if p_client_id is null or p_reply_to is null or length(coalesce(p_body,''))>5000 then raise exception 'Invalid reply';end if;
 perform pg_advisory_xact_lock(hashtextextended(actor||p_client_id::text,0));
 select * into saved from app_private.message_requests where phone=actor and client_id=p_client_id;
 if found then if saved.payload<>request then raise exception 'Request already used';end if;return saved.result;end if;
 if p_kind='direct'then
 perform 1 from public.direct_chat_messages where id=p_reply_to and thread_id=p_id for key share;
 if not found then raise exception 'Reply target unavailable';end if;
 response:=public.send_direct_message(actor,p_id,p_body,p_image_url);
 if response->>'ok'='true'then update public.direct_chat_messages set reply_to=p_reply_to,is_reply=true where id=(response->>'id')::uuid and thread_id=p_id and sender_phone=actor;end if;
 else
 perform 1 from public.live_chat_messages where id=p_reply_to and chat_id=p_id for key share;
 if not found then raise exception 'Reply target unavailable';end if;
 response:=public.send_live_chat_message(actor,p_id,p_body,p_image_url);
 if response->>'ok'='true'then update public.live_chat_messages set reply_to=p_reply_to,is_reply=true where id=(response->>'id')::uuid and chat_id=p_id and sender_phone=actor;end if;
 end if;
 if response->>'ok'='true'then insert into app_private.message_requests(phone,client_id,payload,result)values(actor,p_client_id,request,response);end if;return response;end$$;
create or replace function public.send_chat_message_v429(p_kind text,p_id uuid,p_body text,p_image_url text,p_client_id uuid,p_reply_to uuid)returns jsonb language sql security invoker set search_path='' as $$select app_private.send_chat_message_v429(p_kind,p_id,p_body,p_image_url,p_client_id,p_reply_to)$$;
revoke all on function public.send_chat_message_v429(text,uuid,text,text,uuid,uuid),app_private.send_chat_message_v429(text,uuid,text,text,uuid,uuid)from public,anon;
grant execute on function public.send_chat_message_v429(text,uuid,text,text,uuid,uuid),app_private.send_chat_message_v429(text,uuid,text,text,uuid,uuid)to authenticated;

-- Filtering and LIMIT execute inside each table query so a function scan never materializes the full chat.
create or replace function app_private.chat_page_data(p_kind text,p_id uuid,p_query text default null,p_before timestamptz default null,p_before_id uuid default null,p_message uuid default null,p_limit integer default 50)returns jsonb language plpgsql security definer set search_path='' as $$declare result jsonb;begin
 perform app_private.assert_conversation(p_kind,p_id);
 if p_limit<1 or p_limit>50 then raise exception 'Invalid page size';end if;
 if p_kind='direct'then
 select coalesce(jsonb_agg(x.data order by x.created_at,x.id),'[]')into result from(
 select m.id,m.created_at,to_jsonb(m)||jsonb_build_object('sender_name',p.full_name,'reply',case when r.id is null then null else jsonb_build_object('id',r.id,'sender_name',rp.full_name,'body',left(r.body,300),'has_image',r.image_url is not null)end)data
 from(select * from public.direct_chat_messages where thread_id=p_id and(p_message is null or id=p_message)and(p_before is null or(created_at,id)<(p_before,p_before_id))and(p_query is null or position(lower(p_query)in lower(coalesce(body,'')))>0)order by created_at desc,id desc limit p_limit)m
 left join public.profiles p on p.phone=m.sender_phone left join public.direct_chat_messages r on r.id=m.reply_to and r.thread_id=m.thread_id left join public.profiles rp on rp.phone=r.sender_phone)x;
 else
 select coalesce(jsonb_agg(x.data order by x.created_at,x.id),'[]')into result from(
 select m.id,m.created_at,to_jsonb(m)||jsonb_build_object('sender_name',p.full_name,'reply',case when r.id is null then null else jsonb_build_object('id',r.id,'sender_name',rp.full_name,'body',left(r.body,300),'has_image',r.image_url is not null)end)data
 from(select * from public.live_chat_messages where chat_id=p_id and(p_message is null or id=p_message)and(p_before is null or(created_at,id)<(p_before,p_before_id))and(p_query is null or position(lower(p_query)in lower(coalesce(body,'')))>0)order by created_at desc,id desc limit p_limit)m
 left join public.profiles p on p.phone=m.sender_phone left join public.live_chat_messages r on r.id=m.reply_to and r.chat_id=m.chat_id left join public.profiles rp on rp.phone=r.sender_phone)x;
 end if;return result;end$$;
revoke all on function app_private.chat_page_data(text,uuid,text,timestamptz,uuid,uuid,integer)from public,anon,authenticated;
create or replace function app_private.conversation_page(p_kind text,p_id uuid,p_before timestamptz default null,p_before_id uuid default null)returns jsonb language sql security definer set search_path='' as $$select app_private.chat_page_data(p_kind,p_id,null,p_before,p_before_id,null,50)$$;
create or replace function app_private.search_conversation(p_kind text,p_id uuid,p_query text,p_before timestamptz default null,p_before_id uuid default null)returns jsonb language plpgsql security definer set search_path='' as $$declare q text:=btrim(coalesce(p_query,''));result jsonb;begin
 if length(q)<2 or length(q)>100 then raise exception 'Search needs 2 to 100 characters';end if;
 select coalesce(jsonb_agg(x order by x->>'created_at' desc,x->>'id' desc),'[]')into result from jsonb_array_elements(app_private.chat_page_data(p_kind,p_id,q,p_before,p_before_id,null,25))x;return result;end$$;
create or replace function public.search_conversation(p_kind text,p_id uuid,p_query text,p_before timestamptz default null,p_before_id uuid default null)returns jsonb language sql security invoker set search_path='' as $$select app_private.search_conversation(p_kind,p_id,p_query,p_before,p_before_id)$$;
create or replace function app_private.conversation_target(p_kind text,p_id uuid,p_message_id uuid)returns jsonb language sql security definer set search_path='' as $$select case when p_message_id is null then null else app_private.chat_page_data(p_kind,p_id,null,null,null,p_message_id,1)->0 end$$;
create or replace function public.conversation_target(p_kind text,p_id uuid,p_message_id uuid)returns jsonb language sql security invoker set search_path='' as $$select app_private.conversation_target(p_kind,p_id,p_message_id)$$;
revoke all on function public.search_conversation(text,uuid,text,timestamptz,uuid),app_private.search_conversation(text,uuid,text,timestamptz,uuid),public.conversation_target(text,uuid,uuid),app_private.conversation_target(text,uuid,uuid)from public,anon;
grant execute on function public.search_conversation(text,uuid,text,timestamptz,uuid),app_private.search_conversation(text,uuid,text,timestamptz,uuid),public.conversation_target(text,uuid,uuid),app_private.conversation_target(text,uuid,uuid)to authenticated;

create or replace function app_private.post_target(p_id uuid)returns jsonb language plpgsql security definer set search_path='' as $$declare actor text:=app_private.verified_phone();result jsonb;begin
 select to_jsonb(p)||jsonb_build_object('like_count',(select count(*)from public.post_likes where post_id=p.id),'comment_count',(select count(*)from public.post_comments where post_id=p.id),'liked',exists(select 1 from public.post_likes where post_id=p.id and phone=actor))into result
 from public.posts p join public.profiles me on me.phone=actor join public.profiles author on author.phone=p.author_phone
 where p.id=p_id and(me.is_super_admin or me.admin_level='super'or(p.district=me.district and author.city is not distinct from me.city))and not exists(select 1 from public.user_blocks b where(b.blocker_phone=actor and b.blocked_phone=p.author_phone)or(b.blocker_phone=p.author_phone and b.blocked_phone=actor));return result;end$$;
create or replace function public.post_target(p_id uuid)returns jsonb language sql security invoker set search_path='' as $$select app_private.post_target(p_id)$$;
revoke all on function public.post_target(uuid),app_private.post_target(uuid)from public,anon;
grant execute on function public.post_target(uuid),app_private.post_target(uuid)to authenticated;

notify pgrst,'reload schema';

create or replace function app_private.resolve_notification(p_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare me text:=app_private.verified_phone(); n public.notifications%rowtype; target uuid; result jsonb; prefix text;
begin
 select * into n from public.notifications where id=p_id and recipient_phone=me;
 if not found then raise exception 'Notification unavailable' using errcode='42501'; end if;
 prefix:=split_part(n.source_event,':',1);
 if split_part(coalesce(n.source_event,''),':',2)~*'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'then target:=split_part(n.source_event,':',2)::uuid;end if;
 if prefix='direct' then
  select jsonb_build_object('screen','chat','kind','direct','id',t.id,'messageId',m.id,'other',jsonb_build_object('phone',p.phone,'name',p.full_name,'avatarUrl',p.avatar_url,'district',p.district)) into result
  from public.direct_chat_messages m join public.direct_chat_threads t on t.id=m.thread_id join public.profiles p on p.phone=case when t.user_a=me then t.user_b else t.user_a end
  where m.id=target and me in(t.user_a,t.user_b) and not public.is_user_blocked(me,p.phone);
 elsif prefix='group' then
  select jsonb_build_object('screen','chat','kind','group','id',c.id,'messageId',m.id,'name',c.name) into result from public.live_chat_messages m join public.live_chats c on c.id=m.chat_id
  where m.id=target and exists(select 1 from public.live_chat_members where chat_id=c.id and phone=me);
 elsif prefix='order' then
  select jsonb_build_object('screen',case when provider_phone=me then 'specialistCabinet' else 'myOrders' end,'id',id) into result from public.service_orders where id=target and me in(customer_phone,provider_phone);
 elsif prefix in('daily','myday')then
  if app_private.daily_target(target)is not null then result:=jsonb_build_object('screen','dailyMoment','id',target);end if;
 elsif prefix='hot' then
  select jsonb_build_object('screen','hotNews','id',target)into result from jsonb_array_elements(public.list_hot_news())h where h->>'id'=target::text;
 elsif n.post_id is not null then if app_private.post_target(n.post_id)is not null then result:=jsonb_build_object('screen','home','postId',n.post_id);end if;
 else result:=jsonb_build_object('screen',case when n.kind in ('friend_request','friend_accepted') then 'dailyMoment' else 'notifications' end); end if;
 update public.notifications set is_read=true where id=n.id and recipient_phone=me;
 return coalesce(result,jsonb_build_object('screen','notifications','unavailable',true));
end $$;

notify pgrst,'reload schema';
create or replace function app_private.daily_target(p_id uuid)returns jsonb language plpgsql security definer set search_path='' as $$declare actor text:=app_private.verified_phone();result jsonb;unlocked boolean:=app_private.legacy_has_recent_daily_moment(actor);begin
 select jsonb_build_object('id',d.id,'phone',d.phone,'full_name',p.full_name,'created_at',d.created_at,'caption',d.caption,'locked',d.phone<>actor and not unlocked,'back_image_url',case when d.phone=actor or unlocked then d.back_image_url end,'front_image_url',case when d.phone=actor or unlocked then d.front_image_url end)into result
 from public.daily_moments d join public.profiles p on p.phone=d.phone where d.id=p_id and d.owner_confirmed_at is not null and app_private.daily_visible_at(d.created_at,now()) and not public.is_user_blocked(actor,d.phone)and(d.phone=actor or exists(select 1 from public.daily_photo_friends f where f.user_phone=actor and f.friend_phone=d.phone));
 if result is null then
 select jsonb_build_object('id',d.id,'phone',d.owner_phone,'full_name',p.full_name,'created_at',d.created_at,'caption',d.caption,'locked',false,'back_image_url',d.back_image_url,'front_image_url',d.front_image_url)into result
 from public.my_day_posts d join public.profiles p on p.phone=d.owner_phone where d.id=p_id and app_private.daily_visible_at(d.created_at,now()) and not public.is_user_blocked(actor,d.owner_phone)and(d.owner_phone=actor or exists(select 1 from public.my_day_friendships f where f.status='accepted'and((f.requester_phone=actor and f.addressee_phone=d.owner_phone)or(f.addressee_phone=actor and f.requester_phone=d.owner_phone))));
 end if;return result;end$$;
create or replace function public.daily_target(p_id uuid)returns jsonb language sql security invoker set search_path='' as $$select app_private.daily_target(p_id)$$;
revoke all on function public.daily_target(uuid),app_private.daily_target(uuid)from public,anon;
grant execute on function public.daily_target(uuid),app_private.daily_target(uuid)to authenticated;
notify pgrst,'reload schema';
