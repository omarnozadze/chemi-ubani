-- v4.32.0: apply once after v4.31.0.
create function app_private.has_external_contact_v432(t text)returns boolean language sql immutable set search_path=''as $$select coalesce(t~*'(https?://|www\.|[[:alnum:]._%+-]+@[[:alnum:].-]+\.[a-z]{2,}|(\+?995[ -]*)?5([ -]*[0-9]){8})',false)$$;
revoke all on function app_private.has_external_contact_v432(text)from public,anon,authenticated;
-- Shared city/district catalog copied from the application's registration choices.
create table app_private.location_catalog(city text not null,district text not null,neighborhoods jsonb not null,primary key(city,district));
alter table app_private.location_catalog enable row level security;
revoke all on app_private.location_catalog from public,anon,authenticated;
insert into app_private.location_catalog values
('თბილისი','მთაწმინდა','["მთაწმინდა", "სოლოლაკი", "ვერა", "კიკეთი", "კოჯორი", "ტაბახმელა", "შინდისი"]'::jsonb),
('თბილისი','ვაკე','["ვაკე", "ბაგები", "ვაჟა-ფშაველას კვარტლები", "ნუცუბიძის მიკრორაიონები", "წყნეთი"]'::jsonb),
('თბილისი','საბურთალო','["დიღომი", "აღმაშენებლის ხეივანი", "ვაშლიჯვარი", "ლისი", "საბურთალო", "უნივერსიტეტის უბანი"]'::jsonb),
('თბილისი','კრწანისი','["კრწანისი", "ორთაჭალა", "ფონიჭალა"]'::jsonb),
('თბილისი','ისანი','["ისანი", "ავლაბარი", "მეტრომშენი", "ნავთლუღი", "ვაზისუბანი"]'::jsonb),
('თბილისი','სამგორი','["სამგორი", "ვარკეთილი", "ორხევი", "აეროპორტი", "ლილო"]'::jsonb),
('თბილისი','ჩუღურეთი','["ჩუღურეთი"]'::jsonb),
('თბილისი','დიდუბე','["დიდუბე", "დიღმის მასივი"]'::jsonb),
('თბილისი','ნაძალადევი','["ნაძალადევი", "ლოტკინი", "სანზონა", "თემქა"]'::jsonb),
('თბილისი','გლდანი','["გლდანი", "ავჭალა", "გლდანის ხევი", "მუხიანი"]'::jsonb),
('ბათუმი','ძველი ბათუმი (ისტორიული ცენტრი)','["იაკობ გოგებაშვილის ქუჩა", "აჰმედ მელაშვილის ქუჩა", "ვახტანგ გორგასლის ქუჩა", "ნოდარ დუმბაძის ქუჩა"]'::jsonb),
('ბათუმი','რუსთაველის (საზღვაო) ზოლი','["შოთა რუსთაველის გამზირი", "ნინოშვილის ქუჩა", "ზურაბ გორგილაძის ქუჩა"]'::jsonb),
('ბათუმი','ახალი ბულვარი (ხიმშიაშვილის უბანი)','["შერიფ ხიმშიაშვილის ქუჩა", "კობალაძის ქუჩა", "ინასარიძის ქუჩა", "ფიროსმანის ქუჩა"]'::jsonb),
('ბათუმი','ჭავჭავაძის უბანი','["ილია ჭავჭავაძის ქუჩა", "აკაკი წერეთლის ქუჩა", "26 მაისის ქუჩა"]'::jsonb),
('ბათუმი','ბაგრატიონის / ჯავახიშვილის უბანი','["პეტრე ბაგრატიონის ქუჩა", "მიხეილ ჯავახიშვილის ქუჩა", "ალექსანდრე პუშკინის ქუჩა"]'::jsonb),
('ბათუმი','ბონი-გოროდოკი / ბარცხანა / თამარის დასახლება','["თამარ მეფის გამზირი", "მაიაკოვსკის ქუჩა", "გოგოლის ქუჩა"]'::jsonb),
('ქუთაისი','ცენტრი / ბალახვანი','["დავით აღმაშენებლის გამზირი", "წმინდა ნინოს ქუჩა", "თამარ მეფის ქუჩა", "ცისფერყანწელთა ქუჩა"]'::jsonb),
('ქუთაისი','ძველი ქუთაისი (თეთრი ხიდის მიმდებარე)','["შოთა რუსთაველის გამზირი", "გელათის ქუჩა", "ნიუ-პორტის ქუჩა"]'::jsonb),
('ქუთაისი','საფიჩხია','["ხახანაშვილის ქუჩა", "დობროლიუბოვის ქუჩა", "გორგასლის ქუჩა"]'::jsonb),
('ქუთაისი','ავანგარდი / წერეთლის უბანი','["ილია ჭავჭავაძის გამზირი", "აკაკი წერეთლის ქუჩა", "ირაკლი აბაშიძის ქუჩა"]'::jsonb),
('ქუთაისი','ავტოქარხანა','["გუგუნავას ქუჩა", "ავტოშენებლის ქუჩა", "ხარებავას ქუჩა"]'::jsonb),
('ქუთაისი','ასათიანის უბანი (ხუნდაძე / ზასტავა)','["ლადო ასათიანის ქუჩა", "ნიკეას ქუჩა", "სულხან-საბას გამზირი"]'::jsonb),
('რუსთავი','ძველი რუსთავი (მარჯვენა სანაპირო)','["შოთა რუსთაველის გამზირი", "მერაბ კოსტავას ქუჩა", "დავით აღმაშენებლის ქუჩა", "ფალიაშვილის ქუჩა", "13 ასურელი მამის ქუჩა"]'::jsonb),
('რუსთავი','ახალი რუსთავი (მარცხენა სანაპირო / ცენტრი)','["მეგობრობის გამზირი", "ჟიული შარტავას პროსპექტი", "დავით აღმაშენებლის გამზირი"]'::jsonb),
('რუსთავი','მიკრორაიონები (VII, VIII, XVIII და ა.შ.)','["სილოვან თოდრიას ქუჩა", "გოგლა ლეონიძის ქუჩა", "კლდიაშვილის ქუჩა"]'::jsonb),
('რუსთავი','ჭყონდიდელის დასახლება','["ჭყონდიდელის ქუჩა", "მშვიდობის ქუჩა"]'::jsonb),
('გორი','ცენტრი (ციხის მიმდებარე)','["იოსებ სტალინის გამზირი", "სამეფო ქუჩა", "ქუთაისის ქუჩა"]'::jsonb),
('გორი','წმინდაწყალი','["ილია ჭავჭავაძის გამზირი", "ცხინვალის გზატკეცილი", "შოთა რუსთაველის ქუჩა"]'::jsonb),
('გორი','კომბინატი','["მშვიდობის გამზირი", "ტექსტილშჩიკების ქუჩა", "მოსკოვის ქუჩა"]'::jsonb),
('გორი','ვერხვები','["დავით აღმაშენებლის ქუჩა", "ამილახვრის ქუჩა"]'::jsonb),
('გორი','სადგურის დასახლება','["სადგურის ქუჩა", "წერეთლის ქუჩა"]'::jsonb),
('ზუგდიდი','ცენტრი','["ზვიად გამსახურდიას გამზირი", "შოთა რუსთაველის ქუჩა", "თამარ მეფის ქუჩა", "მერაბ კოსტავას ქუჩა"]'::jsonb),
('ზუგდიდი','რკინიგზის სადგურის უბანი','["ილია ჭავჭავაძის ქუჩა", "სოხუმის ქუჩა", "სადგურის ქუჩა"]'::jsonb),
('ზუგდიდი','კახათის დასახლება / გასასვლელი','["დავით აღმაშენებლის ქუჩა", "კახათის გზატკეცილი"]'::jsonb),
('ზუგდიდი','კომბინატი / ქაღალდკომბინატი','["ჯანაშიას ქუჩა", "ენგურის ქუჩა"]'::jsonb),
('ზუგდიდი','ბარამიას დასახლება','["ხვიჩია ბარამიას ქუჩა"]'::jsonb),
('კახეთი','თელავი — ცენტრი (ბატონის ციხის მიმდებარე)','["ერეკლე II-ის გამზირი", "ვახტანგ ჩორჩანელის ქუჩა"]'::jsonb),
('კახეთი','თელავი — ალაზნის უბანი','["ალაზნის გამზირი", "კავკასიონის ქუჩა"]'::jsonb),
('კახეთი','თელავი — რუსთაველისა და ჭავჭავაძის ზოლი','["შოთა რუსთაველის ქუჩა", "ილია ჭავჭავაძის ქუჩა", "სააკაძის ქუჩა"]'::jsonb);
create function app_private.infer_profile_city()returns trigger language plpgsql security definer set search_path=''as $$begin
 if nullif(trim(new.city),'')is null then select case when count(*)=1 then min(city)end into new.city from app_private.location_catalog where district=new.district;end if;return new;end$$;
revoke all on function app_private.infer_profile_city()from public,anon,authenticated;
create trigger profile_city_normalize before insert or update of city,district on public.profiles for each row execute function app_private.infer_profile_city();
-- Only unambiguous existing districts are repaired. Unknown/corrupt values are left for the owner.
update public.profiles p set city=c.city from(select district,min(city)city from app_private.location_catalog group by district having count(*)=1)c where p.district=c.district and nullif(trim(p.city),'')is null;
create index if not exists profiles_city_district_v432 on public.profiles(city,district);
create index if not exists app_presence_last_seen_v432 on public.app_presence(last_seen,phone);
create function app_private.district_activity_v432(p_touch boolean default false)returns jsonb language plpgsql security definer set search_path=''as $$
declare actor text:=app_private.verified_phone();me public.profiles%rowtype;begin
 select * into me from public.profiles where phone=actor;if not found then raise exception 'Profile required'using errcode='42501';end if;
 if p_touch then insert into public.app_presence(phone,last_seen)values(actor,now())on conflict(phone)do update set last_seen=excluded.last_seen where public.app_presence.last_seen<now()-interval '45 seconds';end if;
 if me.city is null or me.district is null then return jsonb_build_object('needs_location',true);end if;
 return(select jsonb_build_object('city',me.city,'district',me.district,'registered_count',count(*),'online_count',count(*)filter(where a.last_seen>=now()-interval '2 minutes'),'online_window_seconds',120)from public.profiles p left join public.app_presence a on a.phone=p.phone where p.city=me.city and p.district=me.district);end$$;
create function public.district_activity_v432(p_touch boolean default false)returns jsonb language sql security invoker set search_path=''as $$select app_private.district_activity_v432(p_touch)$$;
create function app_private.save_location_v432(p_city text,p_district text,p_neighborhood text)returns jsonb language plpgsql security definer set search_path=''as $$declare actor text:=app_private.verified_phone();begin
 if not exists(select 1 from app_private.location_catalog where city=p_city and district=p_district and(nullif(p_neighborhood,'')is null or neighborhoods?p_neighborhood))then raise exception 'Invalid location';end if;
 update public.profiles set city=p_city,district=p_district,neighborhood=nullif(p_neighborhood,'')where phone=actor;if not found then raise exception 'Profile required';end if;return jsonb_build_object('ok',true);end$$;
create function public.save_location_v432(p_city text,p_district text,p_neighborhood text)returns jsonb language sql security invoker set search_path=''as $$select app_private.save_location_v432(p_city,p_district,p_neighborhood)$$;
alter table public.profiles add column service_profile jsonb;
create function app_private.save_service_profile_v432(p_data jsonb)returns jsonb language plpgsql security definer set search_path=''as $$
declare actor text:=app_private.verified_phone();types text[];d text;sp jsonb:=p_data->'profile';begin
 if p_data is null or octet_length(p_data::text)>12000 then raise exception 'Invalid profile';end if;
 select array_agg(value)into types from jsonb_array_elements_text(p_data->'types');
 if coalesce(cardinality(types),0)not between 1 and 8 or not types<@array['user','plumbing','electric','hvac','handyman','yard','cleaning','pest','lift','security','gardener','hoa','lawyer','accountant','courier','waste','babysitter','tutor','other']then raise exception 'Invalid service type';end if;
 if not 'user'=any(types)then
 if coalesce(jsonb_typeof(sp),'null')<>'object'or not exists(select 1 from app_private.location_catalog where city=sp->>'city')then raise exception 'Service city required';end if;
 if jsonb_array_length(coalesce(sp->'districts','[]'))=0 then raise exception 'Service districts required';end if;
 for d in select value from jsonb_array_elements_text(sp->'districts')loop if not exists(select 1 from app_private.location_catalog where city=sp->>'city'and district=d)then raise exception 'Invalid service district';end if;end loop;
 end if;
 update public.profiles set account_type=types[1],service_profile=jsonb_build_object('types',to_jsonb(types),'otherService',left(p_data->>'otherService',150),'profile',case when 'user'=any(types)then null else sp end)where phone=actor;
 if not found then raise exception 'Profile required';end if;return jsonb_build_object('ok',true);end$$;
create function public.save_service_profile_v432(p_data jsonb)returns jsonb language sql security invoker set search_path=''as $$select app_private.save_service_profile_v432(p_data)$$;
create or replace function app_private.get_verified_profile()returns jsonb language plpgsql security definer set search_path=''as $$declare actor text:=app_private.verified_phone();r jsonb;begin
 select jsonb_build_object('id',id,'phone',phone,'full_name',full_name,'district',district,'neighborhood',neighborhood,'city',city,'account_type',account_type,'is_super_admin',is_super_admin,'admin_level',admin_level,'avatar_url',avatar_url,'service_profile',service_profile)into r from public.profiles where phone=actor;return r;end$$;
-- A city belongs to each listing, independent of the author's residential city.
alter table public.specialist_announcements add column city text;
alter table public.specialist_announcements add column client_request_id uuid;
create unique index specialist_ad_request_v432 on public.specialist_announcements(owner_phone,client_request_id)where client_request_id is not null;
update public.specialist_announcements a set city=c.city from(select a.id,min(l.city)city from public.specialist_announcements a cross join lateral unnest(a.target_districts)d join app_private.location_catalog l on l.district=d group by a.id having count(distinct l.city)=1)c where a.id=c.id and a.city is null;
create index specialist_ad_city_v432 on public.specialist_announcements(city,created_at desc)where status='approved';
create function app_private.submit_specialist_v432(p_data jsonb,p_client_id uuid)returns jsonb language plpgsql security definer set search_path=''as $$
declare actor text:=app_private.verified_phone();target text[];d text;new_id uuid;amount numeric;begin
 if p_client_id is null then raise exception 'Request ID required';end if;
 perform pg_advisory_xact_lock(hashtext(actor),hashtext(p_client_id::text));
 select id into new_id from public.specialist_announcements where owner_phone=actor and client_request_id=p_client_id;if found then return jsonb_build_object('ok',true,'id',new_id);end if;
 if length(trim(coalesce(p_data->>'title','')))not between 1 and 160 or length(trim(coalesce(p_data->>'body','')))not between 1 and 5000 then raise exception 'Invalid title or description';end if;
 amount:=coalesce((p_data->>'price')::numeric,0);if amount<0 or amount>1000000 or amount::text in('NaN','Infinity','-Infinity')then raise exception 'Invalid price';end if;
 select array_agg(distinct value)into target from jsonb_array_elements_text(p_data->'districts');if coalesce(cardinality(target),0)not between 1 and 100 then raise exception 'Choose districts';end if;
 foreach d in array target loop if not exists(select 1 from app_private.location_catalog where city=p_data->>'city'and district=d)then raise exception 'District outside selected city';end if;end loop;
 if app_private.has_external_contact_v432(concat(p_data->>'title',' ',p_data->>'body'))then raise exception 'მიუთითე სერვისის აღწერა გარე კონტაქტის გარეშე.';end if;
 insert into public.specialist_announcements(owner_phone,owner_name,contact_phone,title,body,price,image_url,target_districts,work_hours,status,city,client_request_id)
 select actor,full_name,'',trim(p_data->>'title'),trim(p_data->>'body'),amount,nullif(p_data->>'image',''),target,left(p_data->>'hours',100),'pending',p_data->>'city',p_client_id from public.profiles where phone=actor returning id into new_id;
 if new_id is null then raise exception 'Profile required';end if;return jsonb_build_object('ok',true,'id',new_id);end$$;
create function public.submit_specialist_v432(p_data jsonb,p_client_id uuid)returns jsonb language sql security invoker set search_path=''as $$select app_private.submit_specialist_v432(p_data,p_client_id)$$;
create function app_private.specialist_ads_v432(p_scope text default 'public')returns jsonb language plpgsql security definer set search_path=''as $$
declare actor text:=app_private.verified_phone();me public.profiles%rowtype;r jsonb;begin
 select * into me from public.profiles where phone=actor;
 if p_scope is null or p_scope not in('public','mine','admin')then raise exception 'Invalid scope';end if;
 if p_scope='admin'and not(coalesce(me.is_super_admin,false)or coalesce(me.admin_level='super',false))then raise exception 'Admin required'using errcode='42501';end if;
 select coalesce(jsonb_agg((to_jsonb(x)-'owner_phone'-'contact_phone'-'client_request_id')order by x.created_at desc),'[]')into r from(
 select a.*,coalesce(v.rating_count,0)rating_count,v.rating_average from public.specialist_announcements a
 left join lateral(select count(*)rating_count,round(avg(r.rating)::numeric,1)rating_average from public.service_order_reviews r where r.provider_phone=a.owner_phone and r.rating between 1 and 5)v on true
 where case p_scope when 'mine'then a.owner_phone=actor when 'admin'then true else a.status='approved'and(me.is_super_admin or me.admin_level='super'or(a.city=me.city and me.district=any(a.target_districts)))end
 and(p_scope<>'public'or not public.is_user_blocked(actor,a.owner_phone))order by a.created_at desc limit 100)x;return r;end$$;
create function public.specialist_ads_v432(p_scope text default 'public')returns jsonb language sql security invoker set search_path=''as $$select app_private.specialist_ads_v432(p_scope)$$;
create index if not exists service_reviews_provider_v432 on public.service_order_reviews(provider_phone);
-- Legacy readers keep their shape but receive the same city-scoped public results.
create or replace function app_private.legacy_list_public_specialist_announcements(p_phone text)
returns table(id uuid,owner_phone text,owner_name text,contact_phone text,title text,body text,price numeric,image_url text,target_districts text[],work_hours text,status text,created_at timestamptz)language sql security definer set search_path=''as $$
 select a.id,a.owner_phone,a.owner_name,a.contact_phone,a.title,a.body,a.price,a.image_url,a.target_districts,a.work_hours,a.status,a.created_at
 from jsonb_populate_recordset(null::public.specialist_announcements,app_private.specialist_ads_v432('public'))a
$$;
revoke all on function app_private.legacy_list_public_specialist_announcements(text)from public,anon,authenticated;

create function app_private.register_profile_v432(p_name text,p_city text,p_district text,p_neighborhood text,p_services jsonb)returns jsonb language plpgsql security definer set search_path=''as $$declare r jsonb;begin
 r:=app_private.register_verified_profile(p_name,p_district,p_neighborhood);if r->>'ok'='false'then return r;end if;
 perform app_private.save_location_v432(p_city,p_district,p_neighborhood);perform app_private.save_service_profile_v432(p_services);return r;end$$;
create function public.register_profile_v432(p_name text,p_city text,p_district text,p_neighborhood text,p_services jsonb)returns jsonb language sql security invoker set search_path=''as $$select app_private.register_profile_v432(p_name,p_city,p_district,p_neighborhood,p_services)$$;

do $$declare f record;begin for f in select oid::regprocedure ident from pg_proc where proname='district_activity_v432'and pronamespace in('public'::regnamespace,'app_private'::regnamespace)loop execute format('revoke all on function %s from public,anon',f.ident);execute format('grant execute on function %s to authenticated',f.ident);end loop;end$$;

do $$declare f record;begin for f in select oid::regprocedure ident from pg_proc where proname='save_location_v432'and pronamespace in('public'::regnamespace,'app_private'::regnamespace)loop execute format('revoke all on function %s from public,anon',f.ident);execute format('grant execute on function %s to authenticated',f.ident);end loop;end$$;

do $$declare f record;begin for f in select oid::regprocedure ident from pg_proc where proname='save_service_profile_v432'and pronamespace in('public'::regnamespace,'app_private'::regnamespace)loop execute format('revoke all on function %s from public,anon',f.ident);execute format('grant execute on function %s to authenticated',f.ident);end loop;end$$;

do $$declare f record;begin for f in select oid::regprocedure ident from pg_proc where proname='submit_specialist_v432'and pronamespace in('public'::regnamespace,'app_private'::regnamespace)loop execute format('revoke all on function %s from public,anon',f.ident);execute format('grant execute on function %s to authenticated',f.ident);end loop;end$$;

do $$declare f record;begin for f in select oid::regprocedure ident from pg_proc where proname='specialist_ads_v432'and pronamespace in('public'::regnamespace,'app_private'::regnamespace)loop execute format('revoke all on function %s from public,anon',f.ident);execute format('grant execute on function %s to authenticated',f.ident);end loop;end$$;

do $$declare f record;begin for f in select oid::regprocedure ident from pg_proc where proname='register_profile_v432'and pronamespace in('public'::regnamespace,'app_private'::regnamespace)loop execute format('revoke all on function %s from public,anon',f.ident);execute format('grant execute on function %s to authenticated',f.ident);end loop;end$$;
create function app_private.specialist_reviews_v432(p_ad_id uuid)returns jsonb language plpgsql security definer set search_path=''as $$declare actor text:=app_private.verified_phone();r jsonb;begin
 if not exists(select 1 from jsonb_array_elements(app_private.specialist_ads_v432('public'))a where a->>'id'=p_ad_id::text)then raise exception 'Specialist unavailable'using errcode='42501';end if;
 select coalesce(jsonb_agg(x order by x.created_at desc),'[]')into r from(select v.rating,v.comment,v.created_at,p.full_name reviewer from public.service_order_reviews v join public.specialist_announcements a on a.owner_phone=v.provider_phone join public.profiles p on p.phone=v.customer_phone where a.id=p_ad_id order by v.created_at desc limit 20)x;return r;end$$;
create function public.specialist_reviews_v432(p_ad_id uuid)returns jsonb language sql security invoker set search_path=''as $$select app_private.specialist_reviews_v432(p_ad_id)$$;
revoke all on function public.specialist_reviews_v432(uuid),app_private.specialist_reviews_v432(uuid)from public,anon;grant execute on function public.specialist_reviews_v432(uuid),app_private.specialist_reviews_v432(uuid)to authenticated;

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

alter table public.direct_chat_messages add column attachment jsonb;
alter table public.live_chat_messages add column attachment jsonb;
create function app_private.can_read_chat_file_v432(p_path text)returns boolean language plpgsql stable security definer set search_path=''as $$declare actor text:=app_private.verified_phone();begin
 return exists(select 1 from public.direct_chat_messages m join public.direct_chat_threads t on t.id=m.thread_id where m.attachment->>'path'=p_path and actor in(t.user_a,t.user_b)and not public.is_user_blocked(t.user_a,t.user_b))or exists(select 1 from public.live_chat_messages m join public.live_chat_members c on c.chat_id=m.chat_id and c.phone=actor where m.attachment->>'path'=p_path);
end$$;
revoke all on function app_private.can_read_chat_file_v432(text)from public,anon;grant execute on function app_private.can_read_chat_file_v432(text)to authenticated;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)values('chat-files','chat-files',false,10485760,array['application/pdf','text/plain','application/msword','application/vnd.openxmlformats-officedocument.wordprocessingml.document','audio/webm','audio/ogg','audio/mp4','audio/mpeg','image/jpeg','image/png','image/webp'])on conflict(id)do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;
create policy chat_files_upload_v432 on storage.objects for insert to authenticated with check(bucket_id='chat-files'and split_part(name,'/',1)=app_private.verified_phone()and name~'^[0-9]+/[0-9a-f-]{36}\.[a-z0-9]+$');
create policy chat_files_read_v432 on storage.objects for select to authenticated using(bucket_id='chat-files'and app_private.can_read_chat_file_v432(name));
create function app_private.send_chat_attachment_v432(p_kind text,p_id uuid,p_body text,p_attachment jsonb,p_client_id uuid,p_reply_to uuid default null)returns jsonb language plpgsql security definer set search_path=''as $$
declare actor text:=app_private.verified_phone();request jsonb:=jsonb_build_object('kind',p_kind,'id',p_id,'body',p_body,'attachment',p_attachment,'reply',p_reply_to);saved app_private.message_requests%rowtype;response jsonb;lat numeric;lng numeric;a jsonb;begin
 perform app_private.assert_conversation(p_kind,p_id);
 if p_client_id is null or length(coalesce(p_body,''))>5000 or octet_length(coalesce(p_attachment::text,''))>2000 then raise exception 'Invalid attachment';end if;
 perform pg_advisory_xact_lock(hashtextextended(actor||p_client_id::text,0));select * into saved from app_private.message_requests where phone=actor and client_id=p_client_id;
 if found then if saved.payload<>request then raise exception 'Request already used';end if;return saved.result;end if;
 if p_attachment->>'kind'='location'then
 lat:=(p_attachment->>'lat')::numeric;lng:=(p_attachment->>'lng')::numeric;if lat is null or lng is null or not(lat between -90 and 90)or not(lng between -180 and 180)then raise exception 'Invalid location';end if;
 a:=jsonb_build_object('kind','location','lat',lat,'lng',lng);
 elsif p_attachment->>'kind'in('file','audio')then
 if split_part(p_attachment->>'path','/',1)<>actor or not exists(select 1 from storage.objects where bucket_id='chat-files'and name=p_attachment->>'path')then raise exception 'Attachment unavailable'using errcode='42501';end if;
 a:=jsonb_build_object('kind',p_attachment->>'kind','path',p_attachment->>'path','name',left(p_attachment->>'name',120));
 else raise exception 'Invalid attachment type';end if;
 if p_reply_to is not null then
 if p_kind='direct'and not exists(select 1 from public.direct_chat_messages where id=p_reply_to and thread_id=p_id)or p_kind='group'and not exists(select 1 from public.live_chat_messages where id=p_reply_to and chat_id=p_id)then raise exception 'Reply unavailable';end if;end if;
 if p_kind='direct'then
 response:=public.send_direct_message(actor,p_id,coalesce(nullif(trim(p_body),''),case a->>'kind'when 'location'then '📍 მდებარეობა'when 'audio'then '🎙 ხმოვანი შეტყობინება'else '📎 ფაილი'end),null);
 if response->>'ok'='true'then update public.direct_chat_messages set attachment=a,reply_to=p_reply_to,is_reply=p_reply_to is not null where id=(response->>'id')::uuid;end if;
 else
 response:=public.send_live_chat_message(actor,p_id,coalesce(nullif(trim(p_body),''),'📎 დანართი'),null);
 if response->>'ok'='true'then update public.live_chat_messages set attachment=a,reply_to=p_reply_to,is_reply=p_reply_to is not null where id=(response->>'id')::uuid;end if;end if;
 if response->>'ok'='true'then insert into app_private.message_requests(phone,client_id,payload,result)values(actor,p_client_id,request,response);end if;return response;end$$;
create function public.send_chat_attachment_v432(p_kind text,p_id uuid,p_body text,p_attachment jsonb,p_client_id uuid,p_reply_to uuid default null)returns jsonb language sql security invoker set search_path=''as $$select app_private.send_chat_attachment_v432(p_kind,p_id,p_body,p_attachment,p_client_id,p_reply_to)$$;
revoke all on function public.send_chat_attachment_v432(text,uuid,text,jsonb,uuid,uuid),app_private.send_chat_attachment_v432(text,uuid,text,jsonb,uuid,uuid)from public,anon;
grant execute on function public.send_chat_attachment_v432(text,uuid,text,jsonb,uuid,uuid),app_private.send_chat_attachment_v432(text,uuid,text,jsonb,uuid,uuid)to authenticated;
create function app_private.service_chat_contact_guard_v432()returns trigger language plpgsql security definer set search_path=''as $$begin
 if exists(select 1 from public.service_orders where thread_id=new.thread_id and workflow_version=2)and app_private.has_external_contact_v432(new.body)then raise exception 'სპეციალისტთან შეთანხმებისთვის გამოიყენე აპის ჩათი; გარე კონტაქტი არ მიუთითო.';end if;return new;end$$;
revoke all on function app_private.service_chat_contact_guard_v432()from public,anon,authenticated;
create trigger service_contact_guard before insert or update of body on public.direct_chat_messages for each row execute function app_private.service_chat_contact_guard_v432();

create table app_private.places_quota_v432(actor text not null,slot timestamptz not null,hits integer not null,primary key(actor,slot));
alter table app_private.places_quota_v432 enable row level security;revoke all on app_private.places_quota_v432 from public,anon,authenticated;
create function app_private.places_quota_v432()returns boolean language plpgsql security definer set search_path=''as $$declare v_actor text:=app_private.verified_phone();v_slot timestamptz:=date_trunc('hour',now());counted integer;begin
 perform pg_advisory_xact_lock(432,1);
 delete from app_private.places_quota_v432 q where q.slot<v_slot-interval '2 hours';
 if(select coalesce(sum(hits),0)from app_private.places_quota_v432 q where q.slot=v_slot)>=1000 then return false;end if;
 select hits into counted from app_private.places_quota_v432 q where q.actor=v_actor and q.slot=v_slot;if coalesce(counted,0)>=10 then return false;end if;
 insert into app_private.places_quota_v432 values(v_actor,v_slot,1)on conflict(actor,slot)do update set hits=app_private.places_quota_v432.hits+1;return true;end$$;
create function public.places_quota_v432()returns boolean language sql security invoker set search_path=''as $$select app_private.places_quota_v432()$$;
revoke all on function public.places_quota_v432(),app_private.places_quota_v432()from public,anon;grant execute on function public.places_quota_v432(),app_private.places_quota_v432()to authenticated;

select cron.schedule('market-expiry-v432','*/10 * * * *',$$select app_private.purge_market_v432();$$);
