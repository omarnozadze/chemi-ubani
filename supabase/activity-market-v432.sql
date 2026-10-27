create function app_private.activity_push_preview_v432(p_id uuid)returns jsonb language sql stable security definer set search_path=''as $$
select jsonb_build_object('title',left(case when split_part(n.source_event,':',1)='daily-reminder'then 'ჩემი უბანი • დღის ფოტო'else coalesce(nullif(trim(p.full_name),''),'ჩემი უბანი')end,80),'body',left(case
when split_part(n.source_event,':',1)='direct'then 'შეტყობინება გამოგიგზავნა'
when split_part(n.source_event,':',1)='group'then 'ჯგუფში ახალი შეტყობინება დაწერა'
when split_part(n.source_event,':',1)in('daily','myday')then 'დღის ახალი ფოტო გამოაქვეყნა'
when split_part(n.source_event,':',1)='specialist-review'then 'სპეციალისტის განცხადება დასადასტურებელია'
when split_part(n.source_event,':',1)='business-review'then 'ბიზნესის განაცხადი დასადასტურებელია'
when split_part(n.source_event,':',1)='hot'then 'ცხელი ამბავი: '||n.title
else coalesce(nullif(n.title,''),'ახალი შეტყობინება')end,180))
from public.notifications n left join public.profiles p on p.phone=n.actor_phone where n.id=p_id$$;
revoke all on function app_private.activity_push_preview_v432(uuid)from public,anon,authenticated;
create function app_private.approval_notice_v432()returns trigger language plpgsql security definer set search_path=''as $$declare admin record;prefix text;label text;begin
 if new.status='pending'and(tg_op='INSERT'or old.status is distinct from new.status)then
 prefix:=case when tg_table_name='specialist_announcements'then 'specialist-review'else 'business-review'end;
 label:=case when tg_table_name='specialist_announcements'then 'სპეციალისტის ახალი განცხადება დასადასტურებელია'else 'ბიზნესის ახალი განაცხადი დასადასტურებელია'end;
 for admin in select phone from public.profiles where is_super_admin or admin_level='super'loop
 perform app_private.emit_activity(admin.phone,new.owner_phone,'approval_request',label,prefix||':'||new.id);end loop;end if;return new;end$$;
revoke all on function app_private.approval_notice_v432()from public,anon,authenticated;
create trigger specialist_approval_notice after insert or update of status on public.specialist_announcements for each row execute function app_private.approval_notice_v432();
create trigger business_approval_notice after insert or update of status on public.businesses for each row execute function app_private.approval_notice_v432();
-- Enforce retention even between scheduled purge runs. One month = 30 elapsed days.
create index if not exists market_created_v432 on public.marketplace_listings(created_at);
create function app_private.purge_market_v432()returns integer language plpgsql security definer set search_path=''as $$declare n integer;begin
 delete from public.marketplace_listings where id in(select id from public.marketplace_listings where created_at<=now()-interval '30 days'order by created_at limit 5000);get diagnostics n=row_count;return n;end$$;
revoke all on function app_private.purge_market_v432()from public,anon,authenticated;
create or replace function public.claim_push_batch()returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 update app_private.worker_clock set last_claim=now()where id and last_claim<now()-interval '5 seconds';
 if not found then return '[]';end if;
 update public.push_delivery_log set state='unknown',error_code='ResponseUnknown',updated_at=now() where state='processing'and lease_until<now();
 update public.push_delivery_log set state='retry',next_attempt_at=now(),updated_at=now() where state='leased'and lease_until<now();
 update public.push_delivery_log set state='failed',error_code='RetryExpired',updated_at=now()where state in('pending','retry')and(created_at<now()-interval '2 hours'or attempts>=5);
 update public.push_delivery_log l set state='suppressed',error_code='Preferences',updated_at=now()where l.state in('pending','retry')and not public.push_delivery_allowed(l.notification_id);
 update public.push_delivery_log l set state='no_device',error_code='NoDevice',updated_at=now()where l.state in('pending','retry')and not exists(select 1 from public.push_devices d where d.phone=l.recipient_phone and encode(extensions.digest(d.token,'sha256'),'hex')=l.device_key);
 with candidates as(select id from public.push_delivery_log where state in('pending','retry')and next_attempt_at<=now()order by next_attempt_at,created_at limit 100 for update skip locked),
 claimed as(update public.push_delivery_log l set state='leased',lease_id=gen_random_uuid(),lease_until=now()+interval '2 minutes',updated_at=now()from candidates c where l.id=c.id returning l.*)
 select coalesce(jsonb_agg(jsonb_build_object('id',l.id,'lease_id',l.lease_id,'notification_id',l.notification_id,'token',d.token)||app_private.activity_push_preview_v432(l.notification_id)),'[]')into result from claimed l join public.push_devices d on d.phone=l.recipient_phone and encode(extensions.digest(d.token,'sha256'),'hex')=l.device_key;
 return result;
end $$;
create or replace function app_private.resolve_notification(p_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare me text:=app_private.verified_phone(); n public.notifications%rowtype; target uuid; result jsonb; prefix text;
begin
 select * into n from public.notifications where id=p_id and recipient_phone=me;
 if not found then raise exception 'Notification unavailable' using errcode='42501'; end if;
 prefix:=split_part(n.source_event,':',1);
 if split_part(coalesce(n.source_event,''),':',2)~*'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'then target:=split_part(n.source_event,':',2)::uuid;end if;
 if prefix in('specialist-review','business-review')then
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
CREATE OR REPLACE FUNCTION app_private.legacy_list_marketplace(p_phone text)
 RETURNS TABLE(id uuid, owner_phone text, owner_name text, district text, neighborhood text, title text, description text, category text, price numeric, image_url text, status text, created_at timestamp with time zone)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select m.id,m.owner_phone,m.owner_name,m.district,m.neighborhood,m.title,m.description,m.category,m.price,m.image_url,m.status,m.created_at
 from public.marketplace_listings m
 where m.status='active' and m.created_at>now()-interval '30 days'
 order by m.created_at desc limit 500;
$function$;

CREATE OR REPLACE FUNCTION app_private.legacy_list_public_profile_marketplace(p_viewer_phone text, p_profile_phone text)
 RETURNS TABLE(id uuid, owner_phone text, owner_name text, district text, neighborhood text, title text, description text, category text, price numeric, image_url text, status text, created_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_viewer text:=regexp_replace(coalesce(p_viewer_phone,''),'\D','','g');
  v_target text:=regexp_replace(coalesce(p_profile_phone,''),'\D','','g');
begin
  if not exists(select 1 from public.profiles where profiles.phone=v_viewer) then return; end if;
  return query
  select m.id,m.owner_phone,m.owner_name,m.district,m.neighborhood,m.title,m.description,m.category,m.price,m.image_url,m.status,m.created_at
  from public.marketplace_listings m
  where m.owner_phone=v_target and m.status='active' and m.created_at>now()-interval '30 days'
  order by m.created_at desc
  limit 200;
end $function$;

revoke all on function app_private.legacy_list_marketplace(text),app_private.legacy_list_public_profile_marketplace(text,text)from public,anon,authenticated;
