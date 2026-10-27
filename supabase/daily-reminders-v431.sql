-- Conditional twice-daily reminders; no events are emitted by this migration itself.
create table app_private.daily_reminder_preferences(phone text primary key references public.profiles(phone)on delete cascade,enabled boolean not null default true,updated_at timestamptz not null default now());
alter table app_private.daily_reminder_preferences enable row level security;
revoke all on app_private.daily_reminder_preferences from public,anon,authenticated;
create index if not exists daily_moments_owner_created on public.daily_moments(phone,created_at)where owner_confirmed_at is not null;
create index if not exists my_day_posts_owner_created on public.my_day_posts(owner_phone,created_at);
create or replace function app_private.daily_photo_missing(p_phone text,p_now timestamptz)returns boolean language sql stable security definer set search_path='' as $$
 select not exists(select 1 from public.daily_moments where phone=p_phone and owner_confirmed_at is not null and created_at>=date_trunc('day',p_now at time zone 'Asia/Tbilisi')at time zone 'Asia/Tbilisi'and created_at<=p_now)
 and not exists(select 1 from public.my_day_posts where owner_phone=p_phone and created_at>=date_trunc('day',p_now at time zone 'Asia/Tbilisi')at time zone 'Asia/Tbilisi'and created_at<=p_now)
$$;
revoke all on function app_private.daily_photo_missing(text,timestamptz)from public,anon,authenticated;
create or replace function app_private.daily_reminder_preference(p_enabled boolean default null)returns jsonb language plpgsql security definer set search_path='' as $$declare actor text:=app_private.verified_phone();result jsonb;begin
 if p_enabled is not null then insert into app_private.daily_reminder_preferences(phone,enabled)values(actor,p_enabled)on conflict(phone)do update set enabled=excluded.enabled,updated_at=now();end if;
 select jsonb_build_object('enabled',enabled)into result from app_private.daily_reminder_preferences where phone=actor;return result;end$$;
create or replace function public.daily_reminder_preference(p_enabled boolean default null)returns jsonb language sql security invoker set search_path='' as $$select app_private.daily_reminder_preference(p_enabled)$$;
revoke all on function public.daily_reminder_preference(boolean),app_private.daily_reminder_preference(boolean)from public,anon;
grant execute on function public.daily_reminder_preference(boolean),app_private.daily_reminder_preference(boolean)to authenticated;
create or replace function app_private.enqueue_daily_photo_reminders(p_now timestamptz default now())returns integer language plpgsql security definer set search_path='' as $$
declare stamp timestamp:=p_now at time zone 'Asia/Tbilisi';event_key text;amount integer;begin
 if extract(hour from stamp)not in(8,20)then return 0;end if;
 if not pg_try_advisory_xact_lock(43108020)then return 0;end if;
 event_key:='daily-reminder:'||to_char(stamp,'YYYY-MM-DD:HH24');
 insert into public.notifications(recipient_phone,actor_phone,kind,title,body,source_event)
 select p.phone,null,'daily_photo','დღის ფოტო ჯერ არ დაგიდია','გადაიღე შენი დღის ფოტო და გაუზიარე მეგობრებს.',event_key
 from app_private.daily_reminder_preferences p left join public.notification_preferences n on n.phone=p.phone
 where p.enabled and exists(select 1 from public.push_devices d where d.phone=p.phone)
 and app_private.notification_allowed(to_jsonb(n),'daily_photo',p_now)
 and app_private.daily_photo_missing(p.phone,p_now)
 and not exists(select 1 from public.notifications seen where seen.recipient_phone=p.phone and seen.source_event=event_key)
 order by p.phone limit 2000
 on conflict(recipient_phone,source_event)where source_event is not null do nothing;
 get diagnostics amount=row_count;return amount;end$$;
revoke all on function app_private.enqueue_daily_photo_reminders(timestamptz)from public,anon,authenticated;
-- Recheck immediately before delivery: uploading after enqueue cancels the pending reminder.
create or replace function public.push_delivery_allowed(p_notification_id uuid)returns boolean language sql security definer set search_path='' as $$
 select coalesce((select app_private.notification_allowed(to_jsonb(p),n.kind,now())and
 case when n.source_event like 'daily-reminder:%'then
 n.source_event='daily-reminder:'||to_char(now()at time zone 'Asia/Tbilisi','YYYY-MM-DD:HH24')
 and exists(select 1 from app_private.daily_reminder_preferences r where r.phone=n.recipient_phone and r.enabled)
 and app_private.daily_photo_missing(n.recipient_phone,now())else true end
 from public.notifications n left join public.notification_preferences p on p.phone=n.recipient_phone where n.id=p_notification_id),false)
$$;
revoke all on function public.push_delivery_allowed(uuid)from public,anon,authenticated;
grant execute on function public.push_delivery_allowed(uuid)to service_role;
notify pgrst,'reload schema';

create or replace function app_private.resolve_notification(p_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare me text:=app_private.verified_phone(); n public.notifications%rowtype; target uuid; result jsonb; prefix text;
begin
 select * into n from public.notifications where id=p_id and recipient_phone=me;
 if not found then raise exception 'Notification unavailable' using errcode='42501'; end if;
 prefix:=split_part(n.source_event,':',1);
 if split_part(coalesce(n.source_event,''),':',2)~*'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'then target:=split_part(n.source_event,':',2)::uuid;end if;
 if prefix='daily-reminder'then result:=jsonb_build_object('screen','dailyMoment');
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

