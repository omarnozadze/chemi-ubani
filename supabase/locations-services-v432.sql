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
