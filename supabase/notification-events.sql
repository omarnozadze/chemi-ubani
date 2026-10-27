-- Notification event coverage. No historical events are replayed.
begin;
create or replace function app_private.notification_actor()
returns text language plpgsql security definer set search_path='' as $$
begin
 if auth.role()='service_role' then return '*'; end if;
 return app_private.verified_phone();
exception when insufficient_privilege then return null;
end $$;
revoke all on function app_private.notification_actor() from public,anon,authenticated;

create or replace function app_private.emit_activity(recipient text,actor text,event_kind text,event_title text,event_key text)
returns void language plpgsql security definer set search_path='' as $$
begin
 if recipient is null or recipient=actor then return; end if;
 if exists(select 1 from public.user_blocks b where (b.blocker_phone=recipient and b.blocked_phone=actor) or (b.blocker_phone=actor and b.blocked_phone=recipient)) then return; end if;
 insert into public.notifications(recipient_phone,actor_phone,kind,title,body,source_event)
 values(recipient,actor,event_kind,event_title,'გახსენი აპი დეტალების სანახავად.',event_key)
 on conflict(recipient_phone,source_event) where source_event is not null do nothing;
end $$;
revoke all on function app_private.emit_activity(text,text,text,text,text) from public,anon,authenticated;
alter table public.notifications add column if not exists source_event text;
create unique index if not exists notifications_source_event_unique on public.notifications(recipient_phone,source_event) where source_event is not null;
create index if not exists daily_photo_friends_reverse on public.daily_photo_friends(friend_phone,user_phone);

create or replace function app_private.notify_new_activity()
returns trigger language plpgsql security definer set search_path='' as $$
declare actor text; viewer text; allowed text:=app_private.notification_actor(); peer record; event_kind text; event_title text;
begin
 if allowed is null then return new; end if;
 if tg_table_name in ('direct_chat_messages','live_chat_messages') then
  actor:=new.sender_phone;
  if allowed<>'*' and allowed<>actor then return new; end if;
  if tg_table_name='direct_chat_messages' then
   select case when t.user_a=actor then t.user_b else t.user_a end into viewer from public.direct_chat_threads t where t.id=new.thread_id and actor in(t.user_a,t.user_b);
   perform app_private.emit_activity(viewer,actor,'direct_message','ახალი პირადი შეტყობინება','direct:'||new.id);
  else
   if not exists(select 1 from public.live_chat_members where chat_id=new.chat_id and phone=actor) then return new; end if;
   for peer in select phone from public.live_chat_members where chat_id=new.chat_id loop
    perform app_private.emit_activity(peer.phone,actor,'group_message','ახალი შეტყობინება ჯგუფში','group:'||new.id);
   end loop;
  end if;
 elsif tg_table_name='daily_moments' then
  actor:=new.phone;
  if allowed<>'*' and allowed<>actor then return new; end if;
  if new.owner_confirmed_at is null then return new; end if;
  if tg_op='UPDATE' then if old.owner_confirmed_at is not null then return new; end if; end if;
  for peer in select user_phone as phone from public.daily_photo_friends where friend_phone=actor loop
   perform app_private.emit_activity(peer.phone,actor,'daily_photo','მეგობარმა დღის ფოტო გამოაქვეყნა','daily:'||new.id);
  end loop;
 elsif tg_table_name='my_day_posts' then
  actor:=new.owner_phone;
  if allowed<>'*' and allowed<>actor then return new; end if;
  for peer in select distinct case when requester_phone=actor then addressee_phone else requester_phone end phone from public.my_day_friendships where status='accepted' and actor in(requester_phone,addressee_phone) loop
   perform app_private.emit_activity(peer.phone,actor,'daily_photo','მეგობარმა დღის ფოტო გამოაქვეყნა','myday:'||new.id);
  end loop;
 elsif tg_table_name='service_orders' then
  actor:=case when allowed='*' then new.customer_phone else allowed end;
  if actor not in(new.customer_phone,new.provider_phone) then return new; end if;
  if tg_op='INSERT' then
   viewer:=new.provider_phone; event_kind:='service_order';event_title:='ახალი კონსულტაციის მოთხოვნა';
  else
   if old.status is not distinct from new.status then return new; end if;
   viewer:=case when actor=new.customer_phone then new.provider_phone else new.customer_phone end;
   event_kind:='service_order_update';event_title:='შეკვეთის სტატუსი შეიცვალა';
  end if;
  perform app_private.emit_activity(viewer,actor,event_kind,event_title,'order:'||new.id||':'||new.status||':'||new.updated_at);
 end if;
 return new;
end $$;
revoke all on function app_private.notify_new_activity() from public,anon,authenticated;
drop trigger if exists chat_activity_v423 on public.direct_chat_messages;
drop trigger if exists chat_activity_v423 on public.live_chat_messages;
drop trigger if exists notification_event on public.direct_chat_messages;
create trigger notification_event after insert on public.direct_chat_messages for each row execute function app_private.notify_new_activity();
drop trigger if exists notification_event on public.live_chat_messages;
create trigger notification_event after insert on public.live_chat_messages for each row execute function app_private.notify_new_activity();
drop trigger if exists notification_event on public.daily_moments;
create trigger notification_event after insert or update on public.daily_moments for each row execute function app_private.notify_new_activity();
drop trigger if exists notification_event on public.my_day_posts;
create trigger notification_event after insert on public.my_day_posts for each row execute function app_private.notify_new_activity();
drop trigger if exists notification_event on public.service_orders;
create trigger notification_event after insert or update on public.service_orders for each row execute function app_private.notify_new_activity();

-- Real hot-news publishing replaces the local demonstration feed.
create table if not exists public.hot_news(
 id uuid primary key default gen_random_uuid(),
 author_phone text not null references public.profiles(phone),
 title text not null check(length(title) between 1 and 160),
 body text not null check(length(body) between 1 and 5000),
 category text not null check(category in ('მნიშვნელოვანი','ტრენდი','რეკლამა')),
 district text not null,
 created_at timestamptz not null default now()
);
alter table public.hot_news enable row level security;
revoke all on public.hot_news from anon,authenticated;
create index if not exists hot_news_district_date on public.hot_news(district,created_at desc);
create or replace function app_private.publish_hot_news(p_title text,p_body text,p_category text,p_district text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor text:=app_private.verified_phone(); me public.profiles%rowtype; item public.hot_news%rowtype; peer record;
begin
 select * into me from public.profiles where phone=actor;
 if not coalesce(me.is_super_admin,false) then raise exception 'Administrator required' using errcode='42501'; end if;
 if nullif(trim(p_district),'') is null then raise exception 'District required'; end if;
 insert into public.hot_news(author_phone,title,body,category,district) values(actor,trim(p_title),trim(p_body),p_category,trim(p_district)) returning * into item;
 for peer in select phone from public.profiles where district=item.district loop
  perform app_private.emit_activity(peer.phone,actor,'hot_news','ახალი ცხელი ამბავი შენს რაიონში','hot:'||item.id);
 end loop;
 return jsonb_build_object('ok',true,'id',item.id);
end $$;
create or replace function app_private.list_hot_news()
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor text:=app_private.verified_phone(); result jsonb;
begin
 select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]'::jsonb) into result from (
 select h.id,h.title,h.body,h.category,h.district,h.created_at from public.hot_news h
 join public.profiles p on p.phone=actor where h.district=p.district or p.is_super_admin order by h.created_at desc limit 100
 ) x;
 return result;
end $$;
revoke all on function app_private.publish_hot_news(text,text,text,text),app_private.list_hot_news() from public,anon;
grant execute on function app_private.publish_hot_news(text,text,text,text),app_private.list_hot_news() to authenticated;
create or replace function public.publish_hot_news(p_title text,p_body text,p_category text,p_district text)
returns jsonb language sql security invoker set search_path='' as $$select app_private.publish_hot_news(p_title,p_body,p_category,p_district)$$;
create or replace function public.list_hot_news()
returns jsonb language sql security invoker set search_path='' as $$select app_private.list_hot_news()$$;
revoke all on function public.publish_hot_news(text,text,text,text),public.list_hot_news() from public,anon;
grant execute on function public.publish_hot_news(text,text,text,text),public.list_hot_news() to authenticated;
notify pgrst,'reload schema';
commit;
