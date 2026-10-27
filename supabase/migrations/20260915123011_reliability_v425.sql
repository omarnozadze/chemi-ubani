begin;
create table public.notification_preferences(
 phone text primary key references public.profiles(phone) on delete cascade, enabled boolean not null default true,
 messages boolean not null default true,daily_photo boolean not null default true,reactions boolean not null default true,
 friends boolean not null default true,hot_news boolean not null default true,services boolean not null default true,other boolean not null default true,
 quiet_enabled boolean not null default false,quiet_start integer not null default 1380 check(quiet_start between 0 and 1439),quiet_end integer not null default 480 check(quiet_end between 0 and 1439),updated_at timestamptz not null default now()
);
alter table public.notification_preferences enable row level security;
revoke all on public.notification_preferences from public,anon,authenticated;
create function app_private.get_notification_preferences()returns jsonb language plpgsql security definer set search_path='' as $$
declare actor text:=app_private.verified_phone();r jsonb;begin
 select to_jsonb(p)-'phone' into r from public.notification_preferences p where phone=actor;
 return coalesce(r,'{"enabled":true,"messages":true,"daily_photo":true,"reactions":true,"friends":true,"hot_news":true,"services":true,"other":true,"quiet_enabled":false,"quiet_start":1380,"quiet_end":480}'::jsonb);end $$;
create function app_private.set_notification_preferences(p_settings jsonb)returns jsonb language plpgsql security definer set search_path='' as $$
declare actor text:=app_private.verified_phone();r public.notification_preferences%rowtype;begin
 select * into r from jsonb_populate_record(null::public.notification_preferences,p_settings);
 if r.quiet_enabled and r.quiet_start=r.quiet_end then raise exception 'Quiet hours need different start and end';end if;
 insert into public.notification_preferences(phone,enabled,messages,daily_photo,reactions,friends,hot_news,services,other,quiet_enabled,quiet_start,quiet_end)
 values(actor,r.enabled,r.messages,r.daily_photo,r.reactions,r.friends,r.hot_news,r.services,r.other,r.quiet_enabled,r.quiet_start,r.quiet_end)
 on conflict(phone)do update set enabled=excluded.enabled,messages=excluded.messages,daily_photo=excluded.daily_photo,reactions=excluded.reactions,friends=excluded.friends,hot_news=excluded.hot_news,services=excluded.services,other=excluded.other,quiet_enabled=excluded.quiet_enabled,quiet_start=excluded.quiet_start,quiet_end=excluded.quiet_end,updated_at=now();return app_private.get_notification_preferences();end $$;
create function app_private.notification_allowed(p_settings jsonb,p_kind text,p_now timestamptz)returns boolean language plpgsql immutable set search_path='' as $$
declare category text;minute integer;start_at integer;end_at integer;begin
 if p_settings is null then return true;end if;if not coalesce((p_settings->>'enabled')::boolean,true)then return false;end if;
 category=case when p_kind in('direct_message','group_message')then 'messages' when p_kind='daily_photo'then 'daily_photo'when p_kind like '%like%'or p_kind like '%comment%'then 'reactions'when p_kind like '%friend%'then 'friends'when p_kind='hot_news'then 'hot_news'when p_kind like 'service_order%'then 'services'else 'other'end;
 if not coalesce((p_settings->>category)::boolean,true)then return false;end if;
 if coalesce((p_settings->>'quiet_enabled')::boolean,false)then
 minute=extract(hour from p_now at time zone 'Asia/Tbilisi')::integer*60+extract(minute from p_now at time zone 'Asia/Tbilisi')::integer;start_at=(p_settings->>'quiet_start')::integer;end_at=(p_settings->>'quiet_end')::integer;
 if(start_at<end_at and minute>=start_at and minute<end_at)or(start_at>end_at and(minute>=start_at or minute<end_at))then return false;end if;
 end if;return true;end $$;
create function public.push_delivery_allowed(p_notification_id uuid)returns boolean language sql security definer set search_path='' as $$
 select coalesce((select app_private.notification_allowed(to_jsonb(p),n.kind,now())from public.notifications n left join public.notification_preferences p on p.phone=n.recipient_phone where n.id=p_notification_id),false)
$$;
revoke all on function public.push_delivery_allowed(uuid)from public,anon,authenticated;grant execute on function public.push_delivery_allowed(uuid)to service_role;

-- Private image permissions bind the referenced message's sender to the storage folder owner.
create function app_private.can_read_private_image(p_bucket text,p_name text)returns boolean language plpgsql security definer set search_path='' as $$
declare actor text:=app_private.verified_phone();owner_phone text:=split_part(p_name,'/',1);begin
 if p_bucket not in('chat-images','daily-moments','day-images')then return false;end if;
 if actor=owner_phone then return true;end if;
 if exists(select 1 from public.user_blocks where(blocker_phone=actor and blocked_phone=owner_phone)or(blocker_phone=owner_phone and blocked_phone=actor))then return false;end if;
 if p_bucket='chat-images'then return
 exists(select 1 from public.direct_chat_messages m join public.direct_chat_threads t on t.id=m.thread_id where m.sender_phone=owner_phone and actor in(t.user_a,t.user_b)and split_part(m.image_url,'/chat-images/',2)=p_name)
 or exists(select 1 from public.live_chat_messages m join public.live_chat_members cm on cm.chat_id=m.chat_id where m.sender_phone=owner_phone and cm.phone=actor and split_part(m.image_url,'/chat-images/',2)=p_name);
 elsif p_bucket='daily-moments'then return
 app_private.legacy_has_recent_daily_moment(actor)and exists(select 1 from public.daily_moments d join public.daily_photo_friends f on f.friend_phone=d.phone where d.phone=owner_phone and f.user_phone=actor and d.owner_confirmed_at is not null and app_private.daily_visible_at(d.created_at,now())and(p_name=split_part(d.back_image_url,'/daily-moments/',2)or p_name=split_part(d.front_image_url,'/daily-moments/',2)));
 else return exists(select 1 from public.my_day_posts d join public.my_day_friendships f on f.status='accepted'and((f.requester_phone=actor and f.addressee_phone=d.owner_phone)or(f.addressee_phone=actor and f.requester_phone=d.owner_phone))where d.owner_phone=owner_phone and app_private.daily_visible_at(d.created_at,now())and(p_name=split_part(d.back_image_url,'/day-images/',2)or p_name=split_part(d.front_image_url,'/day-images/',2)));
 end if;end $$;
-- Keyset pages stay stable when multiple messages share a timestamp.
create function app_private.conversation_page(p_kind text,p_id uuid,p_before timestamptz default null,p_before_id uuid default null)returns jsonb language plpgsql security definer set search_path='' as $$
declare actor text:=app_private.verified_phone();r jsonb;begin
 if p_kind='direct'then
 if not exists(select 1 from public.direct_chat_threads where id=p_id and actor in(user_a,user_b))then raise exception 'Membership required'using errcode='42501';end if;
 select coalesce(jsonb_agg(to_jsonb(x)order by x.created_at,x.id),'[]'::jsonb)into r from(select m.*,p.full_name sender_name from public.direct_chat_messages m join public.profiles p on p.phone=m.sender_phone where m.thread_id=p_id and(p_before is null or(m.created_at,m.id)<(p_before,p_before_id))order by m.created_at desc,m.id desc limit 50)x;
 elsif p_kind='group'then
 if not exists(select 1 from public.live_chat_members where chat_id=p_id and phone=actor)then raise exception 'Membership required'using errcode='42501';end if;
 select coalesce(jsonb_agg(to_jsonb(x)order by x.created_at,x.id),'[]'::jsonb)into r from(select m.* from public.live_chat_messages m where m.chat_id=p_id and(p_before is null or(m.created_at,m.id)<(p_before,p_before_id))order by m.created_at desc,m.id desc limit 50)x;
 else raise exception 'Invalid conversation';end if;return r;end $$;
create index if not exists direct_message_cursor on public.direct_chat_messages(thread_id,created_at desc,id desc);
create index if not exists group_message_cursor on public.live_chat_messages(chat_id,created_at desc,id desc);
create function app_private.feed_page(p_before timestamptz default null,p_before_id uuid default null)returns jsonb language plpgsql security definer set search_path='' as $$
declare actor text:=app_private.verified_phone();r jsonb;begin
 select coalesce(jsonb_agg(to_jsonb(x)order by x.created_at desc,x.id desc),'[]'::jsonb)into r from(
 select p.*,(select count(*)from public.post_likes l where l.post_id=p.id)like_count,(select count(*)from public.post_comments c where c.post_id=p.id)comment_count,exists(select 1 from public.post_likes l where l.post_id=p.id and l.phone=actor)liked
 from public.posts p join public.profiles me on me.phone=actor where(me.is_super_admin or me.admin_level='super'or p.district=me.district)
 and(p_before is null or(p.created_at,p.id)<(p_before,p_before_id))order by p.created_at desc,p.id desc limit 25)x;return r;end $$;
create index if not exists post_feed_cursor on public.posts(district,created_at desc,id desc);

-- First-party operational counters, no chat bodies, filenames, tokens or raw stack traces.
create table public.app_presence(phone text primary key references public.profiles(phone)on delete cascade,last_seen timestamptz not null default now());
create table public.app_errors(id bigint generated always as identity primary key,phone text not null,code text not null,screen text not null,version text not null,created_at timestamptz not null default now());
create index app_errors_recent on public.app_errors(created_at desc);
create table public.campaign_events(campaign_id uuid references public.admin_campaigns(id)on delete cascade,phone text not null,kind text not null check(kind in('view','click')),day date not null default(now()at time zone'Asia/Tbilisi')::date,created_at timestamptz not null default now(),primary key(campaign_id,phone,kind,day));
create table public.admin_audit(id bigint generated always as identity primary key,actor_phone text,action text not null,target_id uuid,target_ref text,created_at timestamptz not null default now());
create index admin_audit_recent on public.admin_audit(created_at desc);
alter table public.app_presence enable row level security;alter table public.app_errors enable row level security;alter table public.campaign_events enable row level security;alter table public.admin_audit enable row level security;
revoke all on public.app_presence,public.app_errors,public.campaign_events,public.admin_audit from public,anon,authenticated;
create function app_private.record_app_health(p_code text default null,p_screen text default 'app',p_version text default '4.25.0')returns boolean language plpgsql security definer set search_path='' as $$
declare actor text:=app_private.verified_phone();begin
 insert into public.app_presence(phone)values(actor)on conflict(phone)do update set last_seen=now()where public.app_presence.last_seen<now()-interval '5 minutes';
 if p_code is not null then
 if p_code not in('rpc_failed','upload_failed','image_failed','script_error','promise_error','push_failed','camera_failed','storage_failed')or p_screen!~'^[A-Za-z0-9_-]{1,40}$'or p_version!~'^[0-9.]{1,20}$'then raise exception 'Invalid diagnostic category';end if;
 if(select count(*)from public.app_errors where phone=actor and created_at>now()-interval '1 hour')<20 then insert into public.app_errors(phone,code,screen,version)values(actor,p_code,p_screen,p_version);end if;
 delete from public.app_errors where created_at<now()-interval '30 days';
 end if;return true;end $$;
-- Service-only failure category; notification ownership is looked up on the server.
create function public.record_push_failure(p_notification_id uuid)returns void language plpgsql security definer set search_path='' as $$
declare actor text;begin
 select recipient_phone into actor from public.notifications where id=p_notification_id;
 if actor is not null and(select count(*)from public.app_errors where phone=actor and created_at>now()-interval '1 hour')<20 then
 insert into public.app_errors(phone,code,screen,version)values(actor,'push_failed','server','4.25.0');end if;
 delete from public.app_errors where created_at<now()-interval '30 days';end $$;
revoke all on function public.record_push_failure(uuid)from public,anon,authenticated;
grant execute on function public.record_push_failure(uuid)to service_role;
create function app_private.record_campaign_event(p_id uuid,p_kind text)returns boolean language plpgsql security definer set search_path='' as $$
declare actor text:=app_private.verified_phone();begin
 if p_kind not in('view','click')then raise exception 'Invalid event';end if;
 if not exists(select 1 from public.admin_campaigns c join public.profiles p on p.phone=actor where c.id=p_id and c.status='active'and c.expires_at>now()and c.city=p.city and p.district=any(c.target_districts)and(c.neighborhood is null or c.neighborhood=p.neighborhood))then return false;end if;
 insert into public.campaign_events(campaign_id,phone,kind)values(p_id,actor,p_kind)on conflict do nothing;return true;end $$;
create function app_private.audit_admin_change()returns trigger language plpgsql security definer set search_path='' as $$
declare actor text;item jsonb:=case when tg_op='DELETE'then to_jsonb(old)else to_jsonb(new)end;begin
 begin actor=app_private.verified_phone();exception when insufficient_privilege then actor=null;end;
 if exists(select 1 from public.profiles where phone=actor and(is_super_admin or admin_level='super'))then
 insert into public.admin_audit(actor_phone,action,target_id,target_ref)values(actor,tg_table_name||':'||lower(tg_op),nullif(item->>'id','')::uuid,coalesce(item->>'id',item->>'phone'));
 end if;return case when tg_op='DELETE'then old else new end;end $$;
do $$declare t text;begin foreach t in array array['admin_campaigns','businesses','posts','specialist_announcements','marketplace_listings','profiles','user_reports','service_orders']loop
 if to_regclass('public.'||t)is not null then execute format('create trigger operational_admin_audit after insert or update or delete on public.%I for each row execute function app_private.audit_admin_change()',t);end if;
 end loop;end $$;
create function app_private.admin_operational_stats(p_days integer default 7)returns jsonb language plpgsql security definer set search_path='' as $$
declare actor text:=app_private.verified_phone();since_at timestamptz;begin
 if not exists(select 1 from public.profiles where phone=actor and(is_super_admin or admin_level='super'))then raise exception 'Administrator required'using errcode='42501';end if;
 if p_days not in(1,7,30)then raise exception 'Invalid period';end if;since_at=now()-make_interval(days=>p_days);
 return jsonb_build_object('users',(select count(*)from public.profiles),'active_users',(select count(*)from public.app_presence where last_seen>=since_at),'posts',(select count(*)from public.posts where created_at>=since_at),'campaigns',(select count(*)from public.admin_campaigns where status='active'and expires_at>now()),'groups',(select count(*)from public.live_chats),
 'events',(select coalesce(jsonb_agg(to_jsonb(x)),'[]')from(select c.id,c.title,count(*)filter(where e.kind='view')views,count(*)filter(where e.kind='click')clicks,count(distinct e.phone)reach from public.admin_campaigns c left join public.campaign_events e on e.campaign_id=c.id and e.created_at>=since_at group by c.id order by c.created_at desc limit 100)x),
 'errors',(select coalesce(jsonb_agg(to_jsonb(x)),'[]')from(select code,screen,version,count(*)events,max(created_at)last_seen from public.app_errors where created_at>=since_at group by code,screen,version order by max(created_at)desc limit 50)x),
 'audit',(select coalesce(jsonb_agg(to_jsonb(x)),'[]')from(select action,target_id,target_ref,actor_phone,created_at from public.admin_audit where created_at>=since_at order by created_at desc limit 50)x));end $$;
create or replace function app_private.list_hot_news()
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor text:=app_private.verified_phone();result jsonb;begin
 select coalesce(jsonb_agg(to_jsonb(x)order by x.created_at desc),'[]'::jsonb)into result from(
 select h.id,h.title,h.body,h.category,h.district,h.city,h.neighborhood,h.image_url,h.created_at,h.campaign_id from public.hot_news h
 join public.profiles p on p.phone=actor left join public.admin_campaigns c on c.id=h.campaign_id
 where(h.expires_at is null or h.expires_at>now())and(h.campaign_id is null or c.status='active')
 and ((p.is_super_admin or p.admin_level='super')or(h.district=p.district and(h.city is null or h.city=p.city)and(h.neighborhood is null or h.neighborhood=p.neighborhood)))
 order by h.created_at desc limit 100)x;return result;end $$;

-- Only thin invoker wrappers are exposed; the implementations verify the live session.
do $$declare f record;args text;begin
 for f in select p.oid,p.proname,pg_get_function_arguments(p.oid)signature,pg_get_function_result(p.oid)result,p.proargnames from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='app_private'and p.proname in('get_notification_preferences','set_notification_preferences','can_read_private_image','conversation_page','feed_page','record_app_health','record_campaign_event','admin_operational_stats')loop
 select string_agg(quote_ident(a),',')into args from unnest(f.proargnames)a;
 execute format('create function public.%I(%s) returns %s language sql security invoker set search_path='''' as %L',f.proname,f.signature,f.result,format('select app_private.%I(%s)',f.proname,coalesce(args,'')));
 execute format('revoke all on function %s from public,anon',f.oid::regprocedure);
 execute format('grant execute on function %s to authenticated',f.oid::regprocedure);
 execute format('revoke all on function public.%I(%s) from public,anon',f.proname,pg_get_function_identity_arguments(f.oid));
 execute format('grant execute on function public.%I(%s) to authenticated',f.proname,pg_get_function_identity_arguments(f.oid));
 end loop;end $$;
revoke all on function app_private.notification_allowed(jsonb,text,timestamptz),app_private.audit_admin_change()from public,anon,authenticated;
-- These buckets hold chat/day photos only; public posts and advertisements are unchanged.
drop policy if exists "chat images public read"on storage.objects;
drop policy if exists "daily moments read"on storage.objects;
drop policy if exists "day images public read"on storage.objects;
create policy "private conversation and day image read"on storage.objects for select to authenticated using(bucket_id in('chat-images','daily-moments','day-images')and public.can_read_private_image(bucket_id,name));
update storage.buckets set public=false where id in('chat-images','daily-moments','day-images');
notify pgrst,'reload schema';
commit;
