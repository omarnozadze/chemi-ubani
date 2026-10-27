-- v4.35.0: requires already-applied v4.34.0. One-time migration.
begin;
-- Apply after release-v434.sql. No approximate city bounding boxes are treated as district proof.
-- GPS is device-reported evidence, reviewed by scoped staff; it is not spoof-proof attestation.
create table app_private.location_requests_v435(
 id uuid primary key,phone text not null references public.profiles(phone) on delete cascade,
 old_city text,old_district text,city text not null,district text not null,
 lat double precision not null,lng double precision not null,accuracy double precision not null,
 captured_at timestamptz not null,created_at timestamptz not null default now(),
 status text not null default 'pending' check(status in('pending','approved','rejected','cancelled')),
 reviewed_by text,reviewed_at timestamptz,reason text,
 foreign key(city,district)references app_private.location_catalog(city,district)
);
alter table app_private.location_requests_v435 enable row level security;
revoke all on app_private.location_requests_v435 from public,anon,authenticated;
create unique index location_request_one_pending_v435 on app_private.location_requests_v435(phone)where status='pending';
create index location_requests_review_v435 on app_private.location_requests_v435(city,district,created_at desc)where status='pending';
create table app_private.location_permits_v435(phone text primary key,city text not null,district text not null,request_id uuid not null);
alter table app_private.location_permits_v435 enable row level security;
revoke all on app_private.location_permits_v435 from public,anon,authenticated;
create function app_private.guard_profile_location_v435()returns trigger language plpgsql security definer set search_path=''as $$declare permit uuid;begin
 if(new.city,new.district)is not distinct from(old.city,old.district)then return new;end if;
 -- Initial registration can fill an empty address once. Established addresses require a one-use permit.
 if nullif(trim(old.city),'')is null and nullif(trim(old.district),'')is null then return new;end if;
 delete from app_private.location_permits_v435 where phone=old.phone and city=new.city and district=new.district returning request_id into permit;
 if permit is null then raise exception 'ქალაქის ან რაიონის შეცვლას მდებარეობის დადასტურება სჭირდება.'using errcode='42501';end if;
 return new;end$$;
revoke all on function app_private.guard_profile_location_v435()from public,anon,authenticated;
create trigger zz_profile_location_guard_v435 before update of city,district on public.profiles for each row execute function app_private.guard_profile_location_v435();
-- register_profile inserts district before city; select the requested valid city in that transaction.
create or replace function app_private.register_profile_v432(p_name text,p_city text,p_district text,p_neighborhood text,p_services jsonb)returns jsonb language plpgsql security definer set search_path=''as $$declare actor text:=app_private.verified_phone();begin
 if length(trim(coalesce(p_name,'')))not between 1 and 150 then raise exception 'Invalid name';end if;
 if not exists(select 1 from app_private.location_catalog where city=p_city and district=p_district and(nullif(p_neighborhood,'')is null or neighborhoods?p_neighborhood))then raise exception 'Invalid location';end if;
 if exists(select 1 from public.profiles where phone=actor)then return jsonb_build_object('ok',false,'code','phone_exists');end if;
 insert into public.profiles(phone,full_name,city,district,neighborhood,auth_user_id,phone_verified_at,is_super_admin)values(actor,trim(p_name),p_city,p_district,nullif(p_neighborhood,''),auth.uid(),now(),false);
 perform app_private.save_service_profile_v432(p_services);return jsonb_build_object('ok',true);end$$;
create function app_private.location_request_v435(p_id uuid,p_city text,p_district text,p_lat double precision,p_lng double precision,p_accuracy double precision,p_captured_at timestamptz)returns jsonb language plpgsql security definer set search_path=''as $$
declare actor text:=app_private.verified_phone();me public.profiles%rowtype;existing app_private.location_requests_v435%rowtype;begin
 select *into me from public.profiles where phone=actor for update;if not found then raise exception 'Profile required'using errcode='42501';end if;
 select *into existing from app_private.location_requests_v435 where id=p_id;if found then if existing.phone<>actor then raise exception 'Request unavailable'using errcode='42501';end if;return jsonb_build_object('ok',true,'id',existing.id,'status',existing.status);end if;
 if p_id is null or p_lat is null or p_lng is null or p_accuracy is null or p_captured_at is null or p_lat not between -90 and 90 or p_lng not between -180 and 180 or p_accuracy not between 0 and 100 or p_captured_at<now()-interval '2 minutes' or p_captured_at>now()+interval '15 seconds' then raise exception 'საჭიროა ახალი, ზუსტი მდებარეობა (ცდომილება მაქსიმუმ 100 მეტრი).';end if;
 if(me.city,me.district)is not distinct from(p_city,p_district)then raise exception 'ეს რაიონი უკვე არჩეულია.';end if;
 if not exists(select 1 from app_private.location_catalog where city=p_city and district=p_district)then raise exception 'Invalid location';end if;
 if(select count(*)from app_private.location_requests_v435 where phone=actor and created_at>now()-interval '24 hours')>=3 then raise exception 'დღეს მაქსიმუმ 3 მოთხოვნა შეგიძლია გაგზავნო.';end if;
 if exists(select 1 from app_private.location_requests_v435 where phone=actor and status='pending')then raise exception 'უკვე გაქვს განსახილველი მოთხოვნა.';end if;
 insert into app_private.location_requests_v435(id,phone,old_city,old_district,city,district,lat,lng,accuracy,captured_at)values(p_id,actor,me.city,me.district,p_city,p_district,round(p_lat::numeric,5),round(p_lng::numeric,5),p_accuracy,p_captured_at);
 insert into public.notifications(recipient_phone,actor_phone,kind,title,body,source_event)
 select p.phone,actor,'location_request','რაიონის შეცვლის მოთხოვნა',me.full_name||' • '||p_city||' / '||p_district,'location-review:'||p_id from public.profiles p where p.phone<>actor and(coalesce(p.is_super_admin,false)or p.admin_level='super' or exists(select 1 from app_private.staff_scope_v433 s where s.phone=p.phone and s.role='district'and s.city=p_city and s.district=p_district));
 return jsonb_build_object('ok',true,'id',p_id,'status','pending');end$$;
create function app_private.location_requests_v435(p_manage boolean default false)returns jsonb language plpgsql security definer set search_path=''as $$declare actor text:=app_private.verified_phone();r jsonb;begin
 select coalesce(jsonb_agg(to_jsonb(x)order by x.created_at desc),'[]')into r from(select q.*,p.full_name from app_private.location_requests_v435 q join public.profiles p on p.phone=q.phone where case when p_manage then q.status='pending' and app_private.staff_can_v433('services',q.city,array[q.district])else q.phone=actor end order by q.created_at desc limit 50)x;return r;end$$;
create function app_private.location_decide_v435(p_id uuid,p_action text,p_reason text default null)returns jsonb language plpgsql security definer set search_path=''as $$
declare actor text:=app_private.verified_phone();q app_private.location_requests_v435%rowtype;begin
 select *into q from app_private.location_requests_v435 where id=p_id for update;if not found then raise exception 'Request unavailable'using errcode='42501';end if;
 if p_action='cancelled'then if q.phone<>actor then raise exception 'Own request required'using errcode='42501';end if;
 elsif p_action in('approved','rejected')then if actor=q.phone or not app_private.staff_can_v433('services',q.city,array[q.district])then raise exception 'რაიონის ადმინისტრატორის გადამოწმებაა საჭირო.'using errcode='42501';end if;
 if length(trim(coalesce(p_reason,'')))not between 10 and 500 then raise exception 'მიუთითე გადამოწმების შედეგი (10–500 სიმბოლო).';end if;
 else raise exception 'Invalid action';end if;
 if q.status<>'pending'then raise exception 'მოთხოვნა უკვე განხილულია.';end if;
 if p_action='approved'then
 if q.created_at<now()-interval '24 hours'then raise exception 'მდებარეობის მტკიცებულება მოძველდა; საჭიროა ახალი მოთხოვნა.';end if;
 perform 1 from public.profiles where phone=q.phone and(city,district)is not distinct from(q.old_city,q.old_district)for update;if not found then raise exception 'პროფილის რაიონი უკვე შეიცვალა.';end if;
 insert into app_private.location_permits_v435 values(q.phone,q.city,q.district,q.id);
 update public.profiles set city=q.city,district=q.district,neighborhood=null where phone=q.phone;
 delete from app_private.location_permits_v435 where phone=q.phone;
 end if;
 update app_private.location_requests_v435 set status=p_action,reviewed_by=actor,reviewed_at=now(),reason=left(trim(p_reason),500)where id=q.id;
 if p_action<>'cancelled'then insert into public.notifications(recipient_phone,actor_phone,kind,title,body,source_event)values(q.phone,actor,'location_request',case when p_action='approved'then 'რაიონი განახლდა'else 'რაიონის შეცვლის მოთხოვნა უარყოფილია'end,left(p_reason,500),'location-result:'||q.id);end if;
 return jsonb_build_object('ok',true);end$$;
-- Bounded server-side search; full phone matches only, within the same city and district.
create function app_private.district_people_v435(p_query text default '',p_after text default null,p_chat_id uuid default null)returns jsonb language plpgsql security definer set search_path=''as $$
declare actor text:=app_private.verified_phone();me public.profiles%rowtype;digits text:=regexp_replace(coalesce(p_query,''),'\D','','g');q text:=left(trim(coalesce(p_query,'')),100);r jsonb;begin
 select *into me from public.profiles where phone=actor;if me.city is null or me.district is null then raise exception 'Profile location required'using errcode='42501';end if;
 if length(digits)=12 and left(digits,3)='995'then digits:=right(digits,9);end if;
 if p_chat_id is not null and not exists(select 1 from public.live_chat_members where chat_id=p_chat_id and phone=actor and role in('owner','admin'))then raise exception 'Group admin required'using errcode='42501';end if;
 select coalesce(jsonb_agg(to_jsonb(x)order by x.phone),'[]')into r from(select p.phone,p.full_name,p.city,p.district,p.neighborhood,p.avatar_url from public.profiles p where p.city=me.city and p.district=me.district and p.phone<>actor and not public.is_user_blocked(actor,p.phone)
 and(p_after is null or p.phone>p_after)and(q=''or(length(digits)=9 and p.phone=digits)or(digits=''and length(q)>=2 and position(lower(q)in lower(coalesce(p.full_name,'')))>0))
 and(p_chat_id is null or not exists(select 1 from public.live_chat_members m where m.chat_id=p_chat_id and m.phone=p.phone))order by p.phone limit 51)x;
 return jsonb_build_object('items',case when jsonb_array_length(r)>50 then r-50 else r end,'has_more',jsonb_array_length(r)>50);end$$;
-- Protect old APK endpoints too.
create or replace function app_private.legacy_list_live_chat_candidates(p_phone text)returns table(phone text,full_name text,district text,neighborhood text)language sql security definer set search_path=''as $$
 select x.phone,x.full_name,x.district,x.neighborhood from jsonb_to_recordset(app_private.district_people_v435()->'items')as x(phone text,full_name text,district text,neighborhood text)$$;
create or replace function app_private.legacy_list_live_chat_candidates_v420(p_phone text)returns table(phone text,full_name text,district text,neighborhood text,avatar_url text)language sql security definer set search_path=''as $$
 select x.phone,x.full_name,x.district,x.neighborhood,x.avatar_url from jsonb_to_recordset(app_private.district_people_v435()->'items')as x(phone text,full_name text,district text,neighborhood text,avatar_url text)$$;
create or replace function app_private.legacy_list_live_chat_add_candidates(p_phone text,p_chat_id uuid)returns table(phone text,full_name text,district text,neighborhood text)language sql security definer set search_path=''as $$
 select x.phone,x.full_name,x.district,x.neighborhood from jsonb_to_recordset(app_private.district_people_v435('',null,p_chat_id)->'items')as x(phone text,full_name text,district text,neighborhood text)$$;
create function app_private.guard_group_member_v435()returns trigger language plpgsql security definer set search_path=''as $$declare actor text:=app_private.verified_phone();begin
 if new.phone=actor then return new;end if;
 if not exists(select 1 from public.profiles a join public.profiles b on b.city=a.city and b.district=a.district where a.phone=actor and b.phone=new.phone)or public.is_user_blocked(actor,new.phone)then raise exception 'ჯგუფში მხოლოდ შენი რაიონის მომხმარებელს დაამატებ.'using errcode='42501';end if;return new;end$$;
revoke all on function app_private.guard_group_member_v435()from public,anon,authenticated;
create trigger group_district_guard_v435 before insert on public.live_chat_members for each row execute function app_private.guard_group_member_v435();
create function public.location_request_v435(p_id uuid,p_city text,p_district text,p_lat double precision,p_lng double precision,p_accuracy double precision,p_captured_at timestamptz)returns jsonb language sql security invoker set search_path=''as $$select app_private.location_request_v435(p_id,p_city,p_district,p_lat,p_lng,p_accuracy,p_captured_at)$$;
create function public.location_requests_v435(p_manage boolean default false)returns jsonb language sql security invoker set search_path=''as $$select app_private.location_requests_v435(p_manage)$$;
create function public.location_decide_v435(p_id uuid,p_action text,p_reason text default null)returns jsonb language sql security invoker set search_path=''as $$select app_private.location_decide_v435(p_id,p_action,p_reason)$$;
create function public.district_people_v435(p_query text default '',p_after text default null,p_chat_id uuid default null)returns jsonb language sql security invoker set search_path=''as $$select app_private.district_people_v435(p_query,p_after,p_chat_id)$$;
do $$declare f record;begin for f in select oid::regprocedure ident from pg_proc where proname in('location_request_v435','location_requests_v435','location_decide_v435','district_people_v435')and pronamespace in('public'::regnamespace,'app_private'::regnamespace)loop execute format('revoke all on function %s from public,anon',f.ident);execute format('grant execute on function %s to authenticated',f.ident);end loop;end$$;

create or replace function app_private.resolve_notification(p_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
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

commit;
