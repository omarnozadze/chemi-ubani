-- Service requests have a conversation and explicit, versioned agreement; never a simulated charge.
alter table public.service_orders add column workflow_version integer not null default 1,add column client_request_id uuid,add column thread_id uuid references public.direct_chat_threads(id),add column arrival_from timestamptz,add column arrival_to timestamptz,add column terms_revision integer not null default 0,add column provider_decline_reason text;
alter table public.service_orders drop constraint service_orders_status_check;
alter table public.service_orders add constraint service_orders_status_check check(status in('consultation_requested','accepted','offer_sent','payment_pending','awaiting_customer_reason','funds_held','work_done_pending','done','disputed','refunded','cancelled'));
create unique index service_order_request_v432 on public.service_orders(customer_phone,client_request_id)where client_request_id is not null;
create index service_order_thread_v432 on public.service_orders(thread_id)where thread_id is not null;
create table app_private.service_offers(order_id uuid not null references public.service_orders(id)on delete cascade,revision integer not null,offered_by text not null,amount numeric(12,2)not null,arrival_from timestamptz not null,arrival_to timestamptz not null,note text,expires_at timestamptz not null,created_at timestamptz not null default now(),primary key(order_id,revision));
alter table app_private.service_offers enable row level security;revoke all on app_private.service_offers from public,anon,authenticated;
create function app_private.assert_arrival_v432(a timestamptz,b timestamptz)returns void language plpgsql set search_path=''as $$begin
 if a is null or b is null or not isfinite(a)or not isfinite(b)or a<=now()or b<=a or b-a>interval '24 hours'or a>now()+interval '90 days'then raise exception 'მოსვლის დრო: მომავალი თარიღი, დასაწყისი და დასასრული (მაქს. 24 საათი).';end if;end$$;
create function app_private.create_service_order_v432(p_ad_id uuid,p_description text,p_address text,p_from timestamptz,p_to timestamptz,p_client_id uuid)returns jsonb language plpgsql security definer set search_path=''as $$
declare actor text:=app_private.verified_phone();ad public.specialist_announcements%rowtype;me public.profiles%rowtype;oid uuid;chat jsonb;begin
 if p_client_id is null then raise exception 'Request ID required';end if;perform pg_advisory_xact_lock(hashtext(actor),hashtext(p_client_id::text));
 select id into oid from public.service_orders where customer_phone=actor and client_request_id=p_client_id;if found then return jsonb_build_object('ok',true,'id',oid);end if;
 select * into ad from public.specialist_announcements where id=p_ad_id and status='approved';select * into me from public.profiles where phone=actor;
 if ad.id is null or ad.owner_phone=actor or public.is_user_blocked(actor,ad.owner_phone)then raise exception 'Specialist unavailable'using errcode='42501';end if;
 if not(coalesce(me.is_super_admin,false)or coalesce(me.admin_level='super',false))and(ad.city is distinct from me.city or not me.district=any(ad.target_districts))then raise exception 'Specialist outside selected area'using errcode='42501';end if;
 if length(trim(coalesce(p_description,'')))not between 3 and 3000 or length(trim(coalesce(p_address,'')))not between 3 and 500 then raise exception 'აღწერე სამუშაო და მიუთითე მისამართი.';end if;
 if app_private.has_external_contact_v432(p_description)then raise exception 'კომუნიკაციისთვის გამოიყენე აპის ჩათი; ნომერი ან გარე ბმული არ მიუთითო.';end if;
 perform app_private.assert_arrival_v432(p_from,p_to);chat:=public.start_direct_chat(actor,ad.owner_phone);
 if chat->>'ok'<>'true' or chat->>'id'is null then raise exception 'ჩათი ვერ გაიხსნა: %',coalesce(chat->>'message','შეამოწმე მიმოწერის პარამეტრები');end if;
 insert into public.service_orders(customer_phone,provider_phone,provider_name,category,description,address,requested_time,starting_price,status,workflow_version,client_request_id,thread_id,arrival_from,arrival_to)
 values(actor,ad.owner_phone,ad.owner_name,ad.title,trim(p_description),trim(p_address),p_from,ad.price,'consultation_requested',2,p_client_id,(chat->>'id')::uuid,p_from,p_to)returning id into oid;
 -- The order is the durable context; no automatic private message is sent on behalf of the customer.
 return jsonb_build_object('ok',true,'id',oid);end$$;
create function public.create_service_order_v432(p_ad_id uuid,p_description text,p_address text,p_from timestamptz,p_to timestamptz,p_client_id uuid)returns jsonb language sql security invoker set search_path=''as $$select app_private.create_service_order_v432(p_ad_id,p_description,p_address,p_from,p_to,p_client_id)$$;
create function app_private.service_order_action_v432(p_id uuid,p_action text,p_revision integer,p_amount numeric default null,p_from timestamptz default null,p_to timestamptz default null,p_note text default null)returns jsonb language plpgsql security definer set search_path=''as $$
declare actor text:=app_private.verified_phone();o public.service_orders%rowtype;t app_private.service_offers%rowtype;begin
 select * into o from public.service_orders where id=p_id and actor in(customer_phone,provider_phone)for update;if not found or public.is_user_blocked(o.customer_phone,o.provider_phone)then raise exception 'Order unavailable'using errcode='42501';end if;
 if p_revision is null or p_revision<>o.terms_revision then return jsonb_build_object('ok',false,'code','conflict','message','შეთავაზება შეიცვალა. განაახლე და შეამოწმე ბოლო პირობები.');end if;
 if o.workflow_version<>2 then return jsonb_build_object('ok',false,'message','ეს ძველი შეკვეთაა. ახალი პირობებისთვის შექმენი ახალი მოთხოვნა.');end if;
 if p_action='accept_request'and actor=o.provider_phone and o.status='consultation_requested'then
 update public.service_orders set status='accepted',updated_at=now()where id=p_id;
 elsif p_action='offer'and o.status in('accepted','offer_sent')then
 if actor=o.customer_phone and o.terms_revision=0 then raise exception 'დაელოდე სპეციალისტის პირველ შეთავაზებას.';end if;
 if o.terms_revision>=30 then raise exception 'შეთავაზებების ლიმიტი ამოიწურა; დახურე მოთხოვნა მიზეზის მითითებით.';end if;
 if p_amount is null or p_amount<=0 or p_amount>1000000 or p_amount::text in('NaN','Infinity','-Infinity')or round(p_amount,2)<>p_amount then raise exception 'მიუთითე სწორი ფასი ლარებში.';end if;
 perform app_private.assert_arrival_v432(p_from,p_to);
 if length(coalesce(p_note,''))>1000 or app_private.has_external_contact_v432(p_note)then raise exception 'შენიშვნა მაქს. 1000 სიმბოლო; გარე კონტაქტის გარეშე.';end if;
 insert into app_private.service_offers values(p_id,o.terms_revision+1,actor,p_amount,p_from,p_to,nullif(trim(p_note),''),least(now()+interval '24 hours',p_from),now());
 update public.service_orders set status='offer_sent',terms_revision=o.terms_revision+1,final_price=p_amount,arrival_from=p_from,arrival_to=p_to,updated_at=now()where id=p_id;
 if o.status='offer_sent'then perform app_private.emit_activity(case when actor=o.customer_phone then o.provider_phone else o.customer_phone end,actor,'service_order_update','შეკვეთაზე ახალი ფასი და დრო შემოგთავაზეს','order:'||p_id||':offer:'||(o.terms_revision+1));end if;
 elsif p_action='agree'and o.status='offer_sent'then
 select * into t from app_private.service_offers where order_id=p_id and revision=o.terms_revision;
 if t.offered_by is null or t.offered_by=actor then raise exception 'საკუთარ შეთავაზებას ვერ დაადასტურებ.';end if;
 if t.expires_at<=now()then raise exception 'შეთავაზების ვადა გავიდა. მოითხოვე ახალი პირობები.';end if;
 update public.service_orders set status='payment_pending',funds_held=false,updated_at=now()where id=p_id;
 elsif p_action='decline'and actor=o.provider_phone and o.status in('consultation_requested','accepted','offer_sent','payment_pending')then
 if length(trim(coalesce(p_note,'')))not between 3 and 500 then raise exception 'მიუთითე მიზეზი.';end if;
 update public.service_orders set status='awaiting_customer_reason',provider_decline_reason=trim(p_note),updated_at=now()where id=p_id;
 elsif p_action='cancel'and actor=o.customer_phone and o.status in('consultation_requested','accepted','offer_sent','payment_pending','awaiting_customer_reason')then
 if length(trim(coalesce(p_note,'')))not between 3 and 500 then raise exception 'დახურვის მიზეზი აუცილებელია.';end if;
 update public.service_orders set status='cancelled',cancel_reason=trim(p_note),updated_at=now()where id=p_id;
 else raise exception 'ამ ეტაპზე მოქმედება შეუძლებელია.';end if;return jsonb_build_object('ok',true);end$$;
create function public.service_order_action_v432(p_id uuid,p_action text,p_revision integer,p_amount numeric default null,p_from timestamptz default null,p_to timestamptz default null,p_note text default null)returns jsonb language sql security invoker set search_path=''as $$select app_private.service_order_action_v432(p_id,p_action,p_revision,p_amount,p_from,p_to,p_note)$$;
create function app_private.service_orders_v432(p_side text)returns jsonb language plpgsql security definer set search_path=''as $$
declare actor text:=app_private.verified_phone();r jsonb;begin
 if p_side is null or p_side not in('customer','provider')then raise exception 'Invalid side';end if;
 select coalesce(jsonb_agg(x.data order by x.updated_at desc),'[]')into r from(
 select o.updated_at,(to_jsonb(o)-'customer_phone'-'provider_phone'-'client_request_id')||jsonb_build_object('customer_name',p.full_name,'rating',v.rating,'review_comment',v.comment,'offers',coalesce((select jsonb_agg((to_jsonb(t)-'offered_by')||jsonb_build_object('side',case when t.offered_by=o.customer_phone then 'customer'else 'provider'end)order by t.revision desc)from app_private.service_offers t where t.order_id=o.id),'[]'))data
 from public.service_orders o join public.profiles p on p.phone=o.customer_phone left join public.service_order_reviews v on v.order_id=o.id where case p_side when 'customer'then o.customer_phone=actor else o.provider_phone=actor end order by o.updated_at desc limit 50)x;return r;end$$;
create function public.service_orders_v432(p_side text)returns jsonb language sql security invoker set search_path=''as $$select app_private.service_orders_v432(p_side)$$;
create function app_private.service_chat_v432(p_order_id uuid)returns jsonb language plpgsql security definer set search_path=''as $$declare actor text:=app_private.verified_phone();o public.service_orders%rowtype;r jsonb;begin
 select * into o from public.service_orders where id=p_order_id and actor in(customer_phone,provider_phone);if not found or o.thread_id is null then raise exception 'Order unavailable'using errcode='42501';end if;
 perform app_private.assert_conversation('direct',o.thread_id);
 select jsonb_build_object('id',o.thread_id,'other',jsonb_build_object('name',p.full_name,'avatarUrl',p.avatar_url),'orderId',o.id,'category',o.category,'description',o.description)into r from public.profiles p where p.phone=case when actor=o.customer_phone then o.provider_phone else o.customer_phone end;return r;end$$;
create function public.service_chat_v432(p_order_id uuid)returns jsonb language sql security invoker set search_path=''as $$select app_private.service_chat_v432(p_order_id)$$;
create function app_private.service_reports_v432()returns jsonb language plpgsql security definer set search_path=''as $$declare actor text:=app_private.verified_phone();r jsonb;begin
 perform app_private.require_admin();
 select coalesce(jsonb_agg(x order by x.updated_at desc),'[]')into r from(select o.id,o.category,p.full_name customer_name,o.provider_name,o.status,o.cancel_reason,o.provider_decline_reason,o.final_price,o.updated_at,o.terms_revision from public.service_orders o join public.profiles p on p.phone=o.customer_phone where o.status in('cancelled','awaiting_customer_reason')order by o.updated_at desc limit 100)x;return r;end$$;
create function public.service_reports_v432()returns jsonb language sql security invoker set search_path=''as $$select app_private.service_reports_v432()$$;
create function app_private.service_payment_status_v432(p_order_id uuid default null)returns jsonb language plpgsql security definer set search_path=''as $$declare actor text:=app_private.verified_phone();begin
 if p_order_id is not null and not exists(select 1 from public.service_orders where id=p_order_id and customer_phone=actor)then raise exception 'Order unavailable'using errcode='42501';end if;
 return jsonb_build_object('available',false,'code','provider_not_configured','message','ბარათით გადახდა ჯერ არ არის ჩართული. თანხა არ ჩამოგეჭრება.');end$$;
create function public.service_payment_status_v432(p_order_id uuid default null)returns jsonb language sql security invoker set search_path=''as $$select app_private.service_payment_status_v432(p_order_id)$$;
-- Old clients cannot bypass the new terms workflow or fabricate card holds.
create or replace function public.customer_service_order_action(p_phone text,p_id uuid,p_action text,p_reason text default null)returns jsonb language plpgsql security invoker set search_path=''as $$begin
 perform app_private.assert_actor(p_phone);return app_private.legacy_order_guard_v432(p_id,p_action,p_reason,false,null);end$$;
create or replace function public.provider_service_order_action(p_phone text,p_id uuid,p_action text,p_amount numeric default null,p_reason text default null)returns jsonb language plpgsql security invoker set search_path=''as $$begin
 perform app_private.assert_actor(p_phone);return app_private.legacy_order_guard_v432(p_id,p_action,p_reason,true,p_amount);end$$;
create function app_private.legacy_order_guard_v432(p_id uuid,p_action text,p_reason text,p_provider boolean,p_amount numeric)returns jsonb language plpgsql security definer set search_path=''as $$declare actor text:=app_private.verified_phone();o public.service_orders%rowtype;begin
 select * into o from public.service_orders where id=p_id and case when p_provider then provider_phone=actor else customer_phone=actor end for update;if not found then raise exception 'Order unavailable'using errcode='42501';end if;
 if o.workflow_version=2 then return jsonb_build_object('ok',false,'message','განაახლე აპი ახალი შეთავაზების სანახავად.');end if;
 if p_action='accept_offer'then return jsonb_build_object('ok',false,'message','ბარათით გადახდა ჯერ არ არის ჩართული. თანხა არ ჩამოჭრილა.');end if;
 if p_provider then return app_private.legacy_provider_service_order_action(actor,p_id,p_action,p_amount,p_reason);else return app_private.legacy_customer_service_order_action(actor,p_id,p_action,p_reason);end if;end$$;

do $$declare f record;begin for f in select oid::regprocedure ident from pg_proc where proname='create_service_order_v432'and pronamespace in('public'::regnamespace,'app_private'::regnamespace)loop execute format('revoke all on function %s from public,anon',f.ident);execute format('grant execute on function %s to authenticated',f.ident);end loop;end$$;

do $$declare f record;begin for f in select oid::regprocedure ident from pg_proc where proname='service_order_action_v432'and pronamespace in('public'::regnamespace,'app_private'::regnamespace)loop execute format('revoke all on function %s from public,anon',f.ident);execute format('grant execute on function %s to authenticated',f.ident);end loop;end$$;

do $$declare f record;begin for f in select oid::regprocedure ident from pg_proc where proname='service_orders_v432'and pronamespace in('public'::regnamespace,'app_private'::regnamespace)loop execute format('revoke all on function %s from public,anon',f.ident);execute format('grant execute on function %s to authenticated',f.ident);end loop;end$$;

do $$declare f record;begin for f in select oid::regprocedure ident from pg_proc where proname='service_chat_v432'and pronamespace in('public'::regnamespace,'app_private'::regnamespace)loop execute format('revoke all on function %s from public,anon',f.ident);execute format('grant execute on function %s to authenticated',f.ident);end loop;end$$;

do $$declare f record;begin for f in select oid::regprocedure ident from pg_proc where proname='service_reports_v432'and pronamespace in('public'::regnamespace,'app_private'::regnamespace)loop execute format('revoke all on function %s from public,anon',f.ident);execute format('grant execute on function %s to authenticated',f.ident);end loop;end$$;

do $$declare f record;begin for f in select oid::regprocedure ident from pg_proc where proname='service_payment_status_v432'and pronamespace in('public'::regnamespace,'app_private'::regnamespace)loop execute format('revoke all on function %s from public,anon',f.ident);execute format('grant execute on function %s to authenticated',f.ident);end loop;end$$;

revoke all on function app_private.assert_arrival_v432(timestamptz,timestamptz)from public,anon,authenticated;revoke all on function app_private.legacy_order_guard_v432(uuid,text,text,boolean,numeric)from public,anon;grant execute on function app_private.legacy_order_guard_v432(uuid,text,text,boolean,numeric)to authenticated;
create function app_private.service_thread_v432(p_thread_id uuid)returns jsonb language plpgsql security definer set search_path=''as $$declare r jsonb;begin perform app_private.assert_conversation('direct',p_thread_id);select jsonb_build_object('id',id,'category',category)into r from public.service_orders where thread_id=p_thread_id order by updated_at desc limit 1;return r;end$$;
create function public.service_thread_v432(p_thread_id uuid)returns jsonb language sql security invoker set search_path=''as $$select app_private.service_thread_v432(p_thread_id)$$;
revoke all on function public.service_thread_v432(uuid),app_private.service_thread_v432(uuid)from public,anon;grant execute on function public.service_thread_v432(uuid),app_private.service_thread_v432(uuid)to authenticated;
