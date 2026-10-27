create function app_private.notification_category_v434(p_kind text)returns text language sql immutable set search_path=''as $$select case when p_kind in('direct_message','group_message')then 'messages'when p_kind in('daily_photo','daily_reminder')then 'photos'when p_kind in('service_order','service_order_update','approval_request')then 'services'when p_kind in('hot_news','civic_issue')then 'neighborhood'when p_kind in('post_like','comment','reply','comment_like','friend_request','friend_accepted')then 'social'else 'other'end$$;
revoke all on function app_private.notification_category_v434(text)from public,anon,authenticated;
create index notifications_page_v434 on public.notifications(recipient_phone,created_at desc,id desc);
create function app_private.notifications_page_v434(p_category text default 'all',p_unread boolean default false,p_before timestamptz default null,p_before_id uuid default null)returns jsonb language plpgsql security definer set search_path=''as $$declare actor text:=app_private.verified_phone();r jsonb;begin
 if p_category is null or p_category not in('all','messages','photos','services','neighborhood','social','other')then raise exception 'Invalid category';end if;
 select coalesce(jsonb_agg(to_jsonb(x)order by x.created_at desc,x.id desc),'[]'::jsonb)into r from(select n.id,n.kind,n.title,n.body,n.created_at,coalesce(n.is_read,false)is_read,app_private.notification_category_v434(n.kind)category from public.notifications n where n.recipient_phone=actor and(p_category='all'or app_private.notification_category_v434(n.kind)=p_category)and(not p_unread or not coalesce(n.is_read,false))and(p_before is null or(n.created_at,n.id)<(p_before,p_before_id))order by n.created_at desc,n.id desc limit 30)x;
 return jsonb_build_object('items',r,'through',now());end$$;
create function app_private.notifications_read_all_v434(p_through timestamptz)returns jsonb language plpgsql security definer set search_path=''as $$declare actor text:=app_private.verified_phone();n integer;begin
 if p_through is null or p_through>now()+interval '5 seconds'then raise exception 'Invalid timestamp';end if;
 update public.notifications set is_read=true where recipient_phone=actor and not coalesce(is_read,false)and created_at<=least(p_through,now());get diagnostics n=row_count;return jsonb_build_object('ok',true,'count',n);end$$;
create function public.notifications_page_v434(p_category text default 'all',p_unread boolean default false,p_before timestamptz default null,p_before_id uuid default null)returns jsonb language sql security invoker set search_path=''as $$select app_private.notifications_page_v434(p_category,p_unread,p_before,p_before_id)$$;
create function public.notifications_read_all_v434(p_through timestamptz)returns jsonb language sql security invoker set search_path=''as $$select app_private.notifications_read_all_v434(p_through)$$;
revoke all on function public.notifications_page_v434(text,boolean,timestamptz,uuid),app_private.notifications_page_v434(text,boolean,timestamptz,uuid),public.notifications_read_all_v434(timestamptz),app_private.notifications_read_all_v434(timestamptz)from public,anon;
grant execute on function public.notifications_page_v434(text,boolean,timestamptz,uuid),app_private.notifications_page_v434(text,boolean,timestamptz,uuid),public.notifications_read_all_v434(timestamptz),app_private.notifications_read_all_v434(timestamptz)to authenticated;
create or replace function app_private.resolve_notification(p_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare me text:=app_private.verified_phone(); n public.notifications%rowtype; target uuid; result jsonb; prefix text;
begin
 select * into n from public.notifications where id=p_id and recipient_phone=me;
 if not found then raise exception 'Notification unavailable' using errcode='42501'; end if;
 prefix:=split_part(n.source_event,':',1);
 if split_part(coalesce(n.source_event,''),':',2)~*'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'then target:=split_part(n.source_event,':',2)::uuid;end if;
 if prefix='civic'then
 if app_private.civic_visible_v434(target)then result:=jsonb_build_object('screen','civicIssues434','id',target);end if;
 elsif prefix in('specialist-review','business-review')then
 if exists(select 1 from public.profiles where phone=me and(is_super_admin or admin_level='super'))then result:=jsonb_build_object('screen',case prefix when 'specialist-review'then 'specialistAdsAdmin'else 'businessAdmin'end,'id',target);end if;
 elsif prefix='daily-reminder'then result:=jsonb_build_object('screen','dailyMoment');
 elsif prefix='direct' then
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
