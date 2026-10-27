-- 4.41: unpaid workflow tracking; no money movement, no automatic completion.
alter table public.service_orders add column completion_confirmed boolean not null default false, add column flow_revision integer not null default 0, add column service_city text, add column service_district text;
-- Snapshot existing customer area for staff assignment; private order details stay participant/staff only.
update public.service_orders o set service_city=p.city,service_district=p.district from public.profiles p where p.phone=o.customer_phone;
alter table public.service_orders drop constraint service_orders_status_check;
alter table public.service_orders add constraint service_orders_status_check check(status in('consultation_requested','accepted','offer_sent','payment_pending','awaiting_customer_reason','work_started','funds_held','work_done_pending','done','disputed','refunded','cancelled'));
alter table public.profiles add column service_available boolean not null default true;
alter table public.service_order_reviews add column provider_reply text,add column replied_at timestamptz;
create table app_private.order_events_v441(id bigint generated always as identity primary key,order_id uuid not null references public.service_orders(id)on delete cascade,actor text,action text not null,note text,photo_path text,created_at timestamptz not null default now());
create index order_events_order_v441 on app_private.order_events_v441(order_id,id);
alter table app_private.order_events_v441 enable row level security;revoke all on app_private.order_events_v441 from public,anon,authenticated;
create function app_private.order_staff_v441(p_id uuid)returns boolean language sql stable security definer set search_path=''as $$select exists(select 1 from public.service_orders o where o.id=p_id and app_private.staff_can_v433('services',o.service_city,array[o.service_district]))$$;
create function app_private.order_access_v441(p_id uuid)returns boolean language sql stable security definer set search_path=''as $$select exists(select 1 from public.service_orders where id=p_id and app_private.verified_phone()in(customer_phone,provider_phone))or app_private.order_staff_v441(p_id)$$;
create function app_private.order_insert_v441()returns trigger language plpgsql security definer set search_path=''as $$begin
 if new.workflow_version=2 and exists(select 1 from public.profiles where phone=new.provider_phone and not service_available)then raise exception 'სპეციალისტი დროებით არ იღებს ახალ შეკვეთებს.';end if;
 select city,district into new.service_city,new.service_district from public.profiles where phone=new.customer_phone;return new;end$$;
create trigger order_insert_v441 before insert on public.service_orders for each row execute function app_private.order_insert_v441();
create function app_private.order_audit_v441()returns trigger language plpgsql security definer set search_path=''as $$begin
 if tg_op='INSERT'or new.status is distinct from old.status then insert into app_private.order_events_v441(order_id,actor,action)values(new.id,null,new.status);end if;return new;end$$;
create trigger order_audit_v441 after insert or update of status on public.service_orders for each row execute function app_private.order_audit_v441();
create function app_private.service_availability_v441(p_available boolean default null)returns jsonb language plpgsql security definer set search_path=''as $$declare actor text:=app_private.verified_phone();a boolean;begin
 if p_available is not null then update public.profiles set service_available=p_available where phone=actor;end if;select service_available into a from public.profiles where phone=actor;return jsonb_build_object('available',coalesce(a,true));end$$;
create function public.service_availability_v441(p_available boolean default null)returns jsonb language sql security invoker set search_path=''as $$select app_private.service_availability_v441(p_available)$$;
-- Private evidence is signed only after it is attached to an order the reader can access.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)values('order-evidence','order-evidence',false,5242880,array['image/jpeg','image/png','image/webp']);
create function app_private.order_upload_v441(p_path text)returns boolean language plpgsql stable security definer set search_path=''as $$declare oid uuid;actor text:=app_private.verified_phone();begin
 if auth.uid()is null or split_part(p_path,'/',1)<>auth.uid()::text or p_path!~'^[0-9a-f-]{36}/[0-9a-f-]{36}/[0-9a-f-]{36}\.(jpg|png|webp)$'then return false;end if;
 begin oid:=split_part(p_path,'/',2)::uuid;exception when invalid_text_representation then return false;end;
 return exists(select 1 from public.service_orders where id=oid and actor in(customer_phone,provider_phone)and status in('payment_pending','work_started','work_done_pending','disputed'));
end$$;
create function app_private.order_photo_read_v441(p_path text)returns boolean language sql stable security definer set search_path=''as $$select exists(select 1 from app_private.order_events_v441 e where e.photo_path=p_path and app_private.order_access_v441(e.order_id))$$;
create policy order_evidence_insert_v441 on storage.objects for insert to authenticated with check(bucket_id='order-evidence'and app_private.order_upload_v441(name));
create policy order_evidence_read_v441 on storage.objects for select to authenticated using(bucket_id='order-evidence'and app_private.order_photo_read_v441(name));
create function app_private.order_flow_v441(p_id uuid,p_action text,p_revision integer,p_note text default null,p_photo text default null)returns jsonb language plpgsql security definer set search_path=''as $$
declare actor text:=app_private.verified_phone();o public.service_orders%rowtype;peer record;begin
 select *into o from public.service_orders where id=p_id for update;
 if not found or not(actor in(o.customer_phone,o.provider_phone)or app_private.order_staff_v441(p_id))then raise exception 'შეკვეთა მიუწვდომელია'using errcode='42501';end if;
 if o.workflow_version<>2 then raise exception 'ძველი სატესტო შეკვეთა ამ პროცესში არ მონაწილეობს.';end if;
 if p_revision is distinct from o.flow_revision then raise exception 'შეკვეთა შეიცვალა. განაახლე და სცადე ხელახლა.';end if;
 if length(coalesce(p_note,''))>1500 then raise exception 'განმარტება მაქსიმუმ 1500 სიმბოლო.';end if;
 if p_photo is not null and(not app_private.order_upload_v441(p_photo)or split_part(p_photo,'/',2)<>p_id::text or not exists(select 1 from storage.objects where bucket_id='order-evidence'and name=p_photo))then raise exception 'ფოტო მიუწვდომელია'using errcode='42501';end if;
 if p_action='start'and actor=o.provider_phone and o.status='payment_pending'then
 update public.service_orders set status='work_started'where id=p_id;
 elsif p_action='finish'and actor=o.provider_phone and o.status='work_started'then
 update public.service_orders set status='work_done_pending'where id=p_id;
 elsif p_action='confirm'and actor=o.customer_phone and o.status='work_done_pending'then
 update public.service_orders set status='done',completion_confirmed=true,completed_at=now()where id=p_id;
 elsif p_action='dispute'and actor in(o.customer_phone,o.provider_phone)and o.status in('payment_pending','work_started','work_done_pending')then
 if length(trim(coalesce(p_note,'')))<5 then raise exception 'მიუთითე პრობლემის მიზეზი.';end if;
 update public.service_orders set status='disputed',dispute_reason=trim(p_note)where id=p_id;
 elsif p_action='evidence'and actor in(o.customer_phone,o.provider_phone)and o.status='disputed'then
 if length(trim(coalesce(p_note,'')))<5 then raise exception 'დაამატე განმარტება.';end if;
 if(select count(*)from app_private.order_events_v441 where order_id=p_id and action='evidence')>=30 then raise exception 'ამ დავაზე დამატებების ლიმიტი ამოიწურა.';end if;
 elsif p_action in('resolve_resume','resolve_cancel')and app_private.order_staff_v441(p_id)and actor not in(o.customer_phone,o.provider_phone)and o.status='disputed'then
 if length(trim(coalesce(p_note,'')))<5 then raise exception 'მიუთითე გადაწყვეტილების მიზეზი.';end if;
 update public.service_orders set status=case when p_action='resolve_resume'then 'work_started'else 'cancelled'end,cancel_reason=case when p_action='resolve_cancel'then trim(p_note)else cancel_reason end where id=p_id;
 insert into app_private.moderation_audit_v433(actor,kind,target,action)values(actor,'service_order',p_id,p_action);
 else raise exception 'ამ ეტაპზე მოქმედება შეუძლებელია.'using errcode='42501';end if;
 update public.service_orders set flow_revision=flow_revision+1,updated_at=now()where id=p_id;
 insert into app_private.order_events_v441(order_id,actor,action,note,photo_path)values(p_id,actor,p_action,nullif(trim(p_note),''),p_photo);
 -- Metadata-only alerts; private reason/photo remain inside the authorized order detail.
 for peer in select p.phone from public.profiles p left join app_private.staff_scope_v433 scope on scope.phone=p.phone where p.phone in(o.customer_phone,o.provider_phone)or(p_action='dispute'and(p.is_super_admin or p.admin_level='super'or(scope.role='district'and scope.city=o.service_city and scope.district=o.service_district)))loop
 if peer.phone<>actor and(peer.phone not in(o.customer_phone,o.provider_phone)or p_action='evidence'or actor not in(o.customer_phone,o.provider_phone))then perform app_private.emit_activity(peer.phone,actor,'service_order_update','შეკვეთის სტატუსი განახლდა — გახსენი დეტალები','order:'||p_id||':flow:'||(o.flow_revision+1));end if;end loop;
 return jsonb_build_object('ok',true);end$$;
create function public.order_flow_v441(p_id uuid,p_action text,p_revision integer,p_note text default null,p_photo text default null)returns jsonb language sql security invoker set search_path=''as $$select app_private.order_flow_v441(p_id,p_action,p_revision,p_note,p_photo)$$;
create function app_private.order_staff_for_phone_v441(p_id uuid,p_phone text)returns boolean language sql stable security definer set search_path=''as $$select exists(select 1 from public.service_orders o join public.profiles p on p.phone=p_phone left join app_private.staff_scope_v433 s on s.phone=p.phone where o.id=p_id and(p.is_super_admin or p.admin_level='super'or(s.role='district'and s.city=o.service_city and s.district=o.service_district)))$$;
create function app_private.order_detail_v441(p_id uuid)returns jsonb language plpgsql security definer set search_path=''as $$declare o public.service_orders%rowtype;actor text:=app_private.verified_phone();begin
 if not app_private.order_access_v441(p_id)then raise exception 'შეკვეთა წაიშალა ან მასზე წვდომა აღარ გაქვს.'using errcode='42501';end if;
 select *into o from public.service_orders where id=p_id;
 return(to_jsonb(o)-'customer_phone'-'provider_phone'-'client_request_id')||jsonb_build_object('side',case when actor=o.customer_phone then 'customer'when actor=o.provider_phone then 'provider'else 'staff'end,'can_manage',app_private.order_staff_v441(p_id)and actor not in(o.customer_phone,o.provider_phone),'customer_name',(select full_name from public.profiles where phone=o.customer_phone),'review',(select to_jsonb(v)-'customer_phone'-'provider_phone'from public.service_order_reviews v where v.order_id=p_id),'offers',(select coalesce(jsonb_agg((to_jsonb(t)-'offered_by')||jsonb_build_object('side',case when t.offered_by=o.customer_phone then 'customer'else 'provider'end)order by revision),'[]')from app_private.service_offers t where order_id=p_id),'history',(select coalesce(jsonb_agg((to_jsonb(e)-'actor')||jsonb_build_object('side',case when e.actor=o.customer_phone then 'customer'when e.actor=o.provider_phone then 'provider'when e.actor is null then 'system'else 'staff'end)order by id),'[]')from app_private.order_events_v441 e where order_id=p_id));end$$;
create function public.order_detail_v441(p_id uuid)returns jsonb language sql security invoker set search_path=''as $$select app_private.order_detail_v441(p_id)$$;
create function app_private.order_page_v441(p_side text default 'customer',p_filter text default 'all',p_before timestamptz default null,p_before_id uuid default null)returns jsonb language plpgsql security definer set search_path=''as $$declare actor text:=app_private.verified_phone();r jsonb;begin
 if p_side not in('customer','provider','staff')or p_filter not in('all','waiting','active','done','cancelled','disputed')or p_side is null or p_filter is null then raise exception 'Invalid filter';end if;
 select coalesce(jsonb_agg(to_jsonb(x)order by x.updated_at desc,x.id desc),'[]')into r from(select o.id,o.category,o.status,o.description,o.provider_name,p.full_name customer_name,o.final_price,o.arrival_from,o.updated_at,o.flow_revision,o.workflow_version from public.service_orders o join public.profiles p on p.phone=o.customer_phone where(case p_side when 'customer'then o.customer_phone=actor when 'provider'then o.provider_phone=actor else app_private.order_staff_v441(o.id)and o.status='disputed'end)and(case p_filter when 'all'then true when 'waiting'then o.status in('consultation_requested','accepted','offer_sent','awaiting_customer_reason')when 'active'then o.status in('payment_pending','work_started','work_done_pending','funds_held')else o.status=p_filter end)and(p_before is null or(o.updated_at,o.id)<(p_before,p_before_id))order by o.updated_at desc,o.id desc limit 25)x;return r;end$$;
create function public.order_page_v441(p_side text default 'customer',p_filter text default 'all',p_before timestamptz default null,p_before_id uuid default null)returns jsonb language sql security invoker set search_path=''as $$select app_private.order_page_v441(p_side,p_filter,p_before,p_before_id)$$;
create function app_private.review_order_v441(p_id uuid,p_rating integer,p_comment text default null)returns jsonb language plpgsql security definer set search_path=''as $$declare actor text:=app_private.verified_phone();o public.service_orders%rowtype;begin
 select *into o from public.service_orders where id=p_id and customer_phone=actor for update;
 if not found or o.status<>'done'or not o.completion_confirmed then raise exception 'შეფასება მხოლოდ შენ მიერ დადასტურებული დასრულებული შეკვეთისთვისაა.'using errcode='42501';end if;
 if p_rating is null or p_rating not between 1 and 5 or length(coalesce(p_comment,''))>1000 or app_private.has_external_contact_v432(p_comment)then raise exception 'აირჩიე 1–5 ვარსკვლავი; კომენტარი მაქს. 1000 სიმბოლო, გარე კონტაქტის გარეშე.';end if;
 insert into public.service_order_reviews(order_id,customer_phone,provider_phone,rating,comment)values(p_id,actor,o.provider_phone,p_rating,nullif(trim(p_comment),''))on conflict(order_id)do nothing;
 return jsonb_build_object('ok',true);end$$;
create function public.review_order_v441(p_id uuid,p_rating integer,p_comment text default null)returns jsonb language sql security invoker set search_path=''as $$select app_private.review_order_v441(p_id,p_rating,p_comment)$$;
create function app_private.rate_guard_v441(p_phone text,p_id uuid,p_rating integer,p_comment text)returns jsonb language plpgsql security definer set search_path=''as $$begin perform app_private.assert_actor(p_phone);return app_private.review_order_v441(p_id,p_rating,p_comment);end$$;
create or replace function public.rate_service_order(p_phone text,p_id uuid,p_rating integer,p_comment text default null)returns jsonb language sql security invoker set search_path=''as $$select app_private.rate_guard_v441(p_phone,p_id,p_rating,p_comment)$$;
create function app_private.review_reply_v441(p_id uuid,p_reply text)returns jsonb language plpgsql security definer set search_path=''as $$declare actor text:=app_private.verified_phone();begin
 if length(trim(coalesce(p_reply,'')))not between 3 and 1000 or app_private.has_external_contact_v432(p_reply)then raise exception 'პასუხი: 3–1000 სიმბოლო, გარე კონტაქტის გარეშე.';end if;
 update public.service_order_reviews set provider_reply=trim(p_reply),replied_at=now()where order_id=p_id and provider_phone=actor;
 if not found then raise exception 'შეფასება მიუწვდომელია'using errcode='42501';end if;return jsonb_build_object('ok',true);end$$;
create function public.review_reply_v441(p_id uuid,p_reply text)returns jsonb language sql security invoker set search_path=''as $$select app_private.review_reply_v441(p_id,p_reply)$$;
-- Old administrative endpoint cannot fabricate a payout or completion on the new workflow.
create or replace function public.resolve_service_order_dispute(p_phone text,p_id uuid,p_decision text)returns jsonb language plpgsql security invoker set search_path=''as $$begin raise exception 'დავის განსახილველად გახსენი ახალი შეკვეთის დეტალები.';end$$;
create or replace function app_private.specialist_ads_v432(p_scope text default 'public')returns jsonb language plpgsql security definer set search_path=''as $$
declare actor text:=app_private.verified_phone();me public.profiles%rowtype;r jsonb;begin
 select * into me from public.profiles where phone=actor;
 if p_scope is null or p_scope not in('public','mine','admin')then raise exception 'Invalid scope';end if;
 if p_scope='admin'and not(coalesce(me.is_super_admin,false)or coalesce(me.admin_level='super',false))then raise exception 'Admin required'using errcode='42501';end if;
 select coalesce(jsonb_agg((to_jsonb(x)-'owner_phone'-'contact_phone'-'client_request_id')order by x.created_at desc),'[]')into r from(
 select a.*,(select service_available from public.profiles where phone=a.owner_phone)available,coalesce(v.rating_count,0)rating_count,v.rating_average from public.specialist_announcements a
 left join lateral(select count(*)rating_count,round(avg(r.rating)::numeric,1)rating_average from public.service_order_reviews r join public.service_orders done on done.id=r.order_id and done.status='done' and done.completion_confirmed where r.provider_phone=a.owner_phone and r.rating between 1 and 5)v on true
 where case p_scope when 'mine'then a.owner_phone=actor when 'admin'then true else a.status='approved'and(me.is_super_admin or me.admin_level='super'or(a.city=me.city and me.district=any(a.target_districts)and(a.target_neighborhood is null or a.target_neighborhood=me.neighborhood)))end
 and(p_scope<>'public'or not public.is_user_blocked(actor,a.owner_phone))order by a.created_at desc limit 100)x;return r;end$$;

create or replace function app_private.specialist_reviews_v432(p_ad_id uuid)returns jsonb language plpgsql security definer set search_path=''as $$declare actor text:=app_private.verified_phone();r jsonb;begin
 if not exists(select 1 from jsonb_array_elements(app_private.specialist_ads_v432('public'))a where a->>'id'=p_ad_id::text)then raise exception 'Specialist unavailable'using errcode='42501';end if;
 select coalesce(jsonb_agg(x order by x.created_at desc),'[]')into r from(select v.rating,v.comment,v.created_at,v.provider_reply,v.replied_at,p.full_name reviewer from public.service_order_reviews v join public.service_orders done on done.id=v.order_id and done.status='done' and done.completion_confirmed join public.specialist_announcements a on a.owner_phone=v.provider_phone join public.profiles p on p.phone=v.customer_phone where a.id=p_ad_id order by v.created_at desc limit 20)x;return r;end$$;

alter table app_private.civic_reports_v434 add column resolution_photo_path text;
create or replace function app_private.civic_file_read_v434(p_path text)returns boolean language plpgsql stable security definer set search_path=''as $$begin perform app_private.verified_phone();return exists(select 1 from app_private.civic_reports_v434 r where(p_path=r.photo_path or p_path=r.resolution_photo_path)and app_private.civic_visible_v434(r.id));end$$;
create function app_private.civic_result_v441(p_id uuid,p_revision integer,p_path text)returns jsonb language plpgsql security definer set search_path=''as $$declare r app_private.civic_reports_v434%rowtype;begin
 select *into r from app_private.civic_reports_v434 where id=p_id for update;
 if not found or not app_private.staff_can_v433('civic',r.city,array[r.district])then raise exception 'Forbidden'using errcode='42501';end if;
 if p_revision is distinct from r.revision then raise exception 'განაცხადი შეიცვალა. გახსენი თავიდან.';end if;
 if p_path is null or auth.uid()is null or split_part(p_path,'/',1)is distinct from auth.uid()::text or not exists(select 1 from storage.objects where bucket_id='civic-photos'and name=p_path)then raise exception 'ფოტო მიუწვდომელია'using errcode='42501';end if;
 update app_private.civic_reports_v434 set resolution_photo_path=p_path,revision=revision+1,updated_at=now()where id=p_id;
 insert into app_private.civic_history_v434(report_id,actor,status,note)values(p_id,app_private.verified_phone(),r.status,'დაემატა შედეგის ფოტო.');return jsonb_build_object('ok',true);end$$;
create function public.civic_result_v441(p_id uuid,p_revision integer,p_path text)returns jsonb language sql security invoker set search_path=''as $$select app_private.civic_result_v441(p_id,p_revision,p_path)$$;
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
  select jsonb_build_object('screen',case when me not in(customer_phone,provider_phone)then 'orderReview441'when provider_phone=me then 'specialistCabinet' else 'myOrders' end,'id',id) into result from public.service_orders where id=target and app_private.order_access_v441(id);
 elsif prefix in('daily','myday')then
  if app_private.daily_target(target)is not null then result:=jsonb_build_object('screen','dailyMoment','id',target);end if;
 elsif prefix='hot' then
  select jsonb_build_object('screen','hotNews','id',target)into result from jsonb_array_elements(public.list_hot_news())h where h->>'id'=target::text;
 elsif n.post_id is not null then if app_private.post_target(n.post_id)is not null then result:=jsonb_build_object('screen','home','postId',n.post_id);end if;
 else result:=jsonb_build_object('screen',case when n.kind in ('friend_request','friend_accepted') then 'dailyMoment' else 'notifications' end); end if;
 update public.notifications set is_read=true where id=n.id and recipient_phone=me;
 return coalesce(result,jsonb_build_object('screen','notifications','unavailable',true));
end $$;
-- Public invoker facade, guarded private implementation; no anonymous execution.
do $$declare f record;begin for f in select p.oid::regprocedure ident,p.proname,n.nspname from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in('public','app_private')and p.proname like '%_v441'loop
 execute format('revoke all on function %s from public,anon,authenticated',f.ident);
 if f.proname in('rate_guard_v441','order_flow_v441','order_detail_v441','order_page_v441','service_availability_v441','review_order_v441','review_reply_v441','civic_result_v441','order_upload_v441','order_photo_read_v441')then execute format('grant execute on function %s to authenticated',f.ident);end if;end loop;end$$;
notify pgrst,'reload schema';
