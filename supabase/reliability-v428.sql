-- Verified additive upgrade. Queue holds only hashed device identities.
alter table public.push_delivery_log drop constraint if exists push_delivery_log_state_check;
alter table public.push_delivery_log add constraint push_delivery_log_state_check check(state in('pending','leased','retry','processing','accepted','provider_accepted','failed','suppressed','no_device','unknown','receipt_expired'));
alter table public.push_delivery_log add column if not exists attempts integer not null default 0;
alter table public.push_delivery_log add column if not exists next_attempt_at timestamptz not null default now();
alter table public.push_delivery_log add column if not exists lease_id uuid;
alter table public.push_delivery_log add column if not exists lease_until timestamptz;
create index if not exists push_delivery_due on public.push_delivery_log(next_attempt_at,created_at)where state in('pending','retry');
create index if not exists push_devices_phone on public.push_devices(phone);
create index if not exists hot_news_campaign on public.hot_news(campaign_id);
create index if not exists daily_comments_moment_date on public.daily_moment_comments(moment_id,created_at);
create index if not exists direct_reads_phone on public.direct_chat_reads(phone);
create index if not exists profiles_city_district on public.profiles(city,district);
create table if not exists app_private.worker_clock(id boolean primary key default true check(id),last_claim timestamptz not null default '-infinity',last_tick timestamptz,last_error text);
insert into app_private.worker_clock(id) values(true)on conflict do nothing;
revoke all on app_private.worker_clock from public,anon,authenticated;
alter table app_private.worker_clock enable row level security;

create or replace function public.dispatch_activity_push()returns trigger language plpgsql security definer set search_path='' as $$
begin
 if not public.push_delivery_allowed(new.id)then
 insert into public.push_delivery_log(notification_id,recipient_phone,device_key,state,error_code)values(new.id,new.recipient_phone,'event','suppressed','Preferences')on conflict do nothing;
 else
 insert into public.push_delivery_log(notification_id,recipient_phone,device_key,state)
 select new.id,new.recipient_phone,encode(extensions.digest(d.token,'sha256'),'hex'),'pending' from public.push_devices d where d.phone=new.recipient_phone on conflict do nothing;
 if not found then insert into public.push_delivery_log(notification_id,recipient_phone,device_key,state,error_code)values(new.id,new.recipient_phone,'event','no_device','NoDevice')on conflict do nothing;end if;
 end if;return new;
end $$;

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
 select coalesce(jsonb_agg(jsonb_build_object('id',l.id,'lease_id',l.lease_id,'notification_id',l.notification_id,'token',d.token)),'[]')into result from claimed l join public.push_devices d on d.phone=l.recipient_phone and encode(extensions.digest(d.token,'sha256'),'hex')=l.device_key;
 return result;
end $$;
create or replace function public.start_push_batch(p_jobs jsonb)returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 if jsonb_typeof(p_jobs)<>'array'or jsonb_array_length(p_jobs)>100 then raise exception 'Invalid batch';end if;
 with changed as(update public.push_delivery_log l set state='processing',attempts=attempts+1,updated_at=now()
 from jsonb_to_recordset(p_jobs)as j(id uuid,lease_id uuid)
 where l.id=j.id and l.lease_id=j.lease_id and l.state='leased'and l.lease_until>now() and public.push_delivery_allowed(l.notification_id) returning l.id)
 select coalesce(jsonb_agg(id),'[]')into result from changed;return result;
end $$;
create or replace function public.finish_push_batch(p_results jsonb)returns integer language plpgsql security definer set search_path='' as $$
declare j record; n integer:=0; changed public.push_delivery_log%rowtype;
begin
 if jsonb_typeof(p_results)<>'array'or jsonb_array_length(p_results)>100 then raise exception 'Invalid batch';end if;
 for j in select * from jsonb_to_recordset(p_results)as r(id uuid,lease_id uuid,state text,error_code text,receipt_id text)loop
 if j.state not in('accepted','failed','retry','unknown')or(j.state='accepted'and coalesce(length(j.receipt_id),0)not between 1 and 150)then raise exception 'Invalid result';end if;
 update public.push_delivery_log set state=case when j.state='retry'and attempts>=5 then 'failed'else j.state end,error_code=j.error_code,receipt_id=j.receipt_id,
 next_attempt_at=now()+make_interval(secs=>least(900,15*power(2,attempts)::int)),updated_at=now(),lease_until=null
 where id=j.id and lease_id=j.lease_id and state='processing' returning * into changed;
 if found then n:=n+1;
 if j.error_code='DeviceNotRegistered'then delete from public.push_devices d where d.phone=changed.recipient_phone and encode(extensions.digest(d.token,'sha256'),'hex')=changed.device_key;end if;
 end if;
 end loop;return n;
end $$;
revoke all on function public.claim_push_batch(),public.start_push_batch(jsonb),public.finish_push_batch(jsonb)from public,anon,authenticated;
grant execute on function public.claim_push_batch(),public.start_push_batch(jsonb),public.finish_push_batch(jsonb)to service_role;

-- Bounded atomic rate limits run in the same transaction as successful mutations.
create table if not exists app_private.write_limits(phone text not null,action text not null,window_at timestamptz not null,hits integer not null,primary key(phone,action));
alter table app_private.write_limits enable row level security;
revoke all on app_private.write_limits from public,anon,authenticated;
create or replace function app_private.check_write_limit(p_action text,p_max integer)returns void language plpgsql security definer set search_path='' as $$
declare actor text:=app_private.verified_phone(); n integer;begin
 insert into app_private.write_limits(phone,action,window_at,hits)values(actor,p_action,date_trunc('minute',now()),1)
 on conflict(phone,action)do update set hits=case when write_limits.window_at=excluded.window_at then write_limits.hits+1 else 1 end,window_at=excluded.window_at returning hits into n;
 if n>p_max then raise exception 'ძალიან ხშირი მოქმედებაა. სცადე ერთ წუთში.'using errcode='P0001';end if;
end $$;
revoke all on function app_private.check_write_limit(text,integer)from public,anon,authenticated;

-- Privacy is enforced on inserts, including legacy APIs; no client-only gates.
create table if not exists public.privacy_preferences(phone text primary key references public.profiles(phone)on delete cascade,messages text not null default 'everyone'check(messages in('everyone','friends','nobody')));
alter table public.privacy_preferences enable row level security;
revoke all on public.privacy_preferences from public,anon,authenticated;
create or replace function app_private.are_friends(a text,b text)returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.my_day_friendships where status='accepted'and((requester_phone=a and addressee_phone=b)or(requester_phone=b and addressee_phone=a)))or exists(select 1 from public.daily_photo_friends where user_phone=a and friend_phone=b)$$;
revoke all on function app_private.are_friends(text,text)from public,anon,authenticated;
create or replace function public.get_privacy_preferences()returns jsonb language plpgsql security definer set search_path='' as $$declare actor text:=app_private.verified_phone();begin return coalesce((select to_jsonb(p)-'phone'from public.privacy_preferences p where phone=actor),'{"messages":"everyone"}'::jsonb);end$$;
create or replace function public.set_privacy_preferences(p_messages text)returns jsonb language plpgsql security definer set search_path='' as $$declare actor text:=app_private.verified_phone();begin
 if p_messages not in('everyone','friends','nobody')or p_messages is null then raise exception 'Invalid preferences';end if;
 insert into public.privacy_preferences(phone,messages)values(actor,p_messages)on conflict(phone)do update set messages=excluded.messages;return public.get_privacy_preferences();end$$;
revoke all on function public.get_privacy_preferences(),public.set_privacy_preferences(text)from public,anon;
grant execute on function public.get_privacy_preferences(),public.set_privacy_preferences(text)to authenticated;
create or replace function app_private.guard_social_write()returns trigger language plpgsql security definer set search_path='' as $$
declare actor text;recipient text;preference text;
begin
 -- Applies to client sessions; maintenance without an end-user uid does not consume a user's allowance.
 if auth.uid()is null then return new;end if;
 actor:=app_private.verified_phone();
 if tg_table_name in('direct_chat_messages','direct_messages')then
 if tg_table_name='direct_chat_messages'then select case when user_a=actor then user_b else user_a end into recipient from public.direct_chat_threads where id=new.thread_id and actor in(user_a,user_b);
 else recipient:=new.recipient_phone;end if;
 select messages into preference from public.privacy_preferences where phone=recipient;
 if preference='nobody'or(preference='friends'and not app_private.are_friends(recipient,actor))then raise exception 'მომხმარებელმა პირადი შეტყობინებები შეზღუდა.'using errcode='42501';end if;
 perform app_private.check_write_limit('message',30);
 elsif tg_table_name='live_chat_messages'then perform app_private.check_write_limit('message',30);
 elsif tg_table_name='posts'then perform app_private.check_write_limit('post',3);
 elsif tg_table_name='user_reports'then perform app_private.check_write_limit('report',5);
 end if;return new;
end $$;
revoke all on function app_private.guard_social_write()from public,anon,authenticated;
do $$declare t text;begin foreach t in array array['direct_chat_messages','direct_messages','live_chat_messages','posts','user_reports']loop execute format('drop trigger if exists social_write_guard on public.%I',t);execute format('create trigger social_write_guard before insert on public.%I for each row execute function app_private.guard_social_write()',t);end loop;end$$;
notify pgrst,'reload schema';

-- Search shares the feed's verified-account scope and does not accept a caller's phone.
create or replace function public.search_feed(p_query text default '',p_before timestamptz default null,p_before_id uuid default null)returns jsonb language plpgsql security definer set search_path='' as $$
declare actor text:=app_private.verified_phone();r jsonb;q text:=btrim(coalesce(p_query,''));begin
 if length(q)>100 then raise exception 'Search is too long';end if;
 select coalesce(jsonb_agg(to_jsonb(x)order by x.created_at desc,x.id desc),'[]'::jsonb)into r from(
 select p.*,(select count(*)from public.post_likes l where l.post_id=p.id)like_count,(select count(*)from public.post_comments c where c.post_id=p.id)comment_count,exists(select 1 from public.post_likes l where l.post_id=p.id and l.phone=actor)liked
 from public.posts p join public.profiles me on me.phone=actor join public.profiles author on author.phone=p.author_phone
 where(me.is_super_admin or me.admin_level='super'or(p.district=me.district and author.city is not distinct from me.city))
 and not exists(select 1 from public.user_blocks b where(b.blocker_phone=actor and b.blocked_phone=p.author_phone)or(b.blocker_phone=p.author_phone and b.blocked_phone=actor))
 and(q=''or position(lower(q)in lower(coalesce(p.content,'')||' '||coalesce(p.author_name,'')))>0)
 and(p_before is null or(p.created_at,p.id)<(p_before,p_before_id))order by p.created_at desc,p.id desc limit 25)x;return r;end $$;
revoke all on function public.search_feed(text,timestamptz,uuid)from public,anon;
grant execute on function public.search_feed(text,timestamptz,uuid)to authenticated;
create or replace function app_private.feed_page(p_before timestamptz default null,p_before_id uuid default null)returns jsonb language sql security definer set search_path='' as $$select public.search_feed('',p_before,p_before_id)$$;

create index if not exists push_delivery_receipts on public.push_delivery_log(updated_at,created_at)where state='accepted';
create index if not exists app_errors_phone_recent on public.app_errors(phone,created_at desc);

create or replace function app_private.district_registered_count(p_phone text)returns table(district text,registered_count bigint)language plpgsql stable security definer set search_path='' as $$
declare actor text:=app_private.verified_phone();area text;city_name text;super_admin boolean;begin
 if regexp_replace(coalesce(p_phone,''),'[^0-9]','','g')<>actor then raise exception 'Account mismatch'using errcode='42501';end if;
 select p.district,p.city,coalesce(p.is_super_admin,false)or coalesce(p.admin_level='super',false)into area,city_name,super_admin from public.profiles p where p.phone=actor;
 if not found then raise exception 'Profile required'using errcode='42501';end if;
 if super_admin then return query select 'ყველა რაიონი'::text,count(*)from public.profiles;
 else return query select coalesce(area,''),count(*)from public.profiles p where p.district=area and p.city is not distinct from city_name;end if;end $$;
create or replace function public.district_registered_count(p_phone text)returns table(district text,registered_count bigint)language sql security invoker set search_path='' as $$select * from app_private.district_registered_count(p_phone)$$;
revoke all on function app_private.district_registered_count(text),public.district_registered_count(text)from public,anon;
grant execute on function app_private.district_registered_count(text),public.district_registered_count(text)to authenticated;

create or replace function public.admin_delivery_summary()returns jsonb language plpgsql security definer set search_path='' as $$declare actor text:=app_private.verified_phone();begin
 if not exists(select 1 from public.profiles where phone=actor and(is_super_admin or admin_level='super'))then raise exception 'Superadmin required'using errcode='42501';end if;
 return jsonb_build_object('waiting',(select count(*)from public.push_delivery_log where state in('pending','retry','leased')),'unknown',(select count(*)from public.push_delivery_log where state='unknown'and created_at>now()-interval '24 hours'),'failed',(select count(*)from public.push_delivery_log where state='failed'and created_at>now()-interval '24 hours'),'oldest_pending',(select min(created_at)from public.push_delivery_log where state in('pending','retry')),'worker',(select jsonb_build_object('last_tick',last_tick,'last_claim',case when isfinite(last_claim)then last_claim else null end,'error',last_error)from app_private.worker_clock where id));end$$;
revoke all on function public.admin_delivery_summary()from public,anon;
grant execute on function public.admin_delivery_summary()to authenticated;
notify pgrst,'reload schema';
