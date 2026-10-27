-- Support opens a direct thread without sending a message; additions notify only the new member.
set lock_timeout='3s';
set statement_timeout='20s';
update public.profiles set full_name='ადმინისტრატორი'
where phone='500000000' and (is_super_admin or admin_level='super');
create or replace function app_private.start_support_chat_v445()
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor text:=app_private.verified_phone();owner_phone text;chat jsonb;
begin
 select phone into owner_phone from public.profiles where phone='500000000'and(is_super_admin or admin_level='super');
 if owner_phone is null or actor=owner_phone or public.is_user_blocked(actor,owner_phone)then raise exception 'მიმოწერა მიუწვდომელია.'using errcode='42501';end if;
 chat:=public.start_direct_chat(actor,owner_phone);
 if chat->>'ok' is distinct from 'true' or chat->>'id' is null then raise exception 'მიმოწერა ვერ გაიხსნა.';end if;
 return chat||jsonb_build_object('other',jsonb_build_object('phone',owner_phone,'name','ადმინისტრატორი'));
end$$;
create or replace function public.start_support_chat_v445()
returns jsonb language sql security invoker set search_path='' as $$select app_private.start_support_chat_v445()$$;
revoke all on function app_private.start_support_chat_v445(),public.start_support_chat_v445()from public,anon;
grant execute on function app_private.start_support_chat_v445(),public.start_support_chat_v445()to authenticated;
create or replace function app_private.group_added_v445()
returns trigger language plpgsql security definer set search_path='' as $$
declare actor text:=app_private.verified_phone();group_name text;
begin
 if new.phone=actor then return new;end if;
 if not exists(select 1 from public.live_chat_members where chat_id=new.chat_id and phone=actor and role in('owner','admin'))then return new;end if;
 select name into group_name from public.live_chats where id=new.chat_id;
 perform app_private.emit_activity(new.phone,actor,'group_message','დაგამატეს ჯგუფში „'||left(coalesce(group_name,'ჯგუფი'),100)||'“','group-added:'||new.chat_id||':'||gen_random_uuid());
 return new;
end$$;
revoke all on function app_private.group_added_v445()from public,anon,authenticated;
drop trigger if exists notify_group_added_v445 on public.live_chat_members;
create trigger notify_group_added_v445 after insert on public.live_chat_members for each row execute function app_private.group_added_v445();

CREATE OR REPLACE FUNCTION public.push_delivery_allowed(p_notification_id uuid)
 RETURNS boolean
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select coalesce((select app_private.notification_allowed(to_jsonb(p),n.kind,now())and
 case when n.source_event like 'daily-reminder:%'then
 n.source_event='daily-reminder:'||to_char(now()at time zone 'Asia/Tbilisi','YYYY-MM-DD:HH24')
 and exists(select 1 from app_private.daily_reminder_preferences r where r.phone=n.recipient_phone and r.enabled)
 and app_private.daily_photo_missing(n.recipient_phone,now())else true end
 and(coalesce(p.advertising,true)or not exists(select 1 from public.hot_news h where n.source_event='hot:'||h.id and h.category='რეკლამა'))
 and not exists(select 1 from public.live_chat_messages m join app_private.group_mutes_v440 g on g.chat_id=m.chat_id and g.phone=n.recipient_phone where n.source_event='group:'||m.id)
 and (coalesce(n.source_event,'') not like 'group-added:%' or (exists(select 1 from public.live_chat_members m where m.chat_id::text=split_part(n.source_event,':',2) and m.phone=n.recipient_phone) and not exists(select 1 from app_private.group_mutes_v440 g where g.chat_id::text=split_part(n.source_event,':',2) and g.phone=n.recipient_phone) and not public.is_user_blocked(n.actor_phone,n.recipient_phone)))
 from public.notifications n left join public.notification_preferences p on p.phone=n.recipient_phone where n.id=p_notification_id),false)$function$
;

CREATE OR REPLACE FUNCTION app_private.resolve_notification(p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare me text:=app_private.verified_phone(); n public.notifications%rowtype; target uuid; result jsonb; prefix text;
begin
 select * into n from public.notifications where id=p_id and recipient_phone=me;
 if not found then raise exception 'Notification unavailable' using errcode='42501'; end if;
 prefix:=split_part(n.source_event,':',1);
 if split_part(coalesce(n.source_event,''),':',2)~*'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'then target:=split_part(n.source_event,':',2)::uuid;end if;
 if prefix in('location-review','location-result')then
 if exists(select 1 from app_private.location_requests_v435 q where q.id=target and(q.phone=me or app_private.staff_can_v433('services',q.city,array[q.district])))then result:=jsonb_build_object('screen','locationRequests435','manage',prefix='location-review');end if;
 elsif prefix='civic'then
 if app_private.civic_visible_v434(target)then result:=jsonb_build_object('screen','civicIssues434','id',target);end if;
 elsif prefix in('specialist-review','business-review')then
 if exists(select 1 from public.profiles where phone=me and(is_super_admin or admin_level='super'))then result:=jsonb_build_object('screen',case prefix when 'specialist-review'then 'specialistAdsAdmin'else 'businessAdmin'end,'id',target);end if;
 elsif prefix='daily-reminder'then result:=jsonb_build_object('screen','dailyMoment');
 elsif prefix='direct' then
  select jsonb_build_object('screen','chat','kind','direct','id',t.id,'messageId',m.id,'other',jsonb_build_object('phone',p.phone,'name',p.full_name,'avatarUrl',p.avatar_url,'district',p.district)) into result
  from public.direct_chat_messages m join public.direct_chat_threads t on t.id=m.thread_id join public.profiles p on p.phone=case when t.user_a=me then t.user_b else t.user_a end
  where m.id=target and me in(t.user_a,t.user_b) and not public.is_user_blocked(me,p.phone);
 elsif prefix='group-added' then
  select jsonb_build_object('screen','chat','kind','group','id',c.id,'name',c.name) into result from public.live_chats c where c.id=target and exists(select 1 from public.live_chat_members where chat_id=c.id and phone=me);
 elsif prefix='group' then
  select jsonb_build_object('screen','chat','kind','group','id',c.id,'messageId',m.id,'name',c.name) into result from public.live_chat_messages m join public.live_chats c on c.id=m.chat_id
  where m.id=target and exists(select 1 from public.live_chat_members where chat_id=c.id and phone=me);
 elsif prefix='order' then
  select jsonb_build_object('screen',case when me not in(customer_phone,provider_phone)then 'orderReview441'when provider_phone=me then 'specialistCabinet' else 'myOrders' end,'id',id) into result from public.service_orders where id=target and app_private.order_access_v441(id);
 elsif prefix in('daily','myday')then
  if app_private.daily_target(target)is not null then result:=jsonb_build_object('screen','dailyMoment','id',target);end if;
 elsif prefix='hot' then
  select jsonb_build_object('screen','hotNews','id',target)into result from jsonb_array_elements(public.list_hot_news())h where h->>'id'=target::text;
 elsif n.post_id is not null then if app_private.post_target(n.post_id)is not null then result:=jsonb_build_object('screen','home','postId',n.post_id);end if;
 else result:=jsonb_build_object('screen',case when n.kind in ('friend_request','friend_accepted') then 'dailyMoment' else 'notifications' end); end if;
 update public.notifications set is_read=true where id=n.id and recipient_phone=me;
 return coalesce(result,jsonb_build_object('screen','notifications','unavailable',true));
end $function$
;

notify pgrst,'reload schema';
