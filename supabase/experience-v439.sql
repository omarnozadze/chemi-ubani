-- Additive UX repairs. Does not send test messages or delete user content.
alter table public.service_orders add column if not exists location_lat double precision,add column if not exists location_lng double precision;
alter table public.service_orders add constraint service_order_pin_v439 check((location_lat is null and location_lng is null)or(location_lat between -90 and 90 and location_lng between -180 and 180 and location_lat is not null and location_lng is not null));
create or replace function app_private.assert_arrival_v432(a timestamptz,b timestamptz)returns void language plpgsql set search_path=''as $$begin
 if a is null or b is null or not isfinite(a)or not isfinite(b)or a<=now()or b<=a then raise exception 'აირჩიე მომავალი დაწყების დრო და მასზე გვიან დასრულება.';end if;end$$;
create function app_private.create_service_order_v439(p_ad_id uuid,p_description text,p_address text,p_from timestamptz,p_to timestamptz,p_client_id uuid,p_lat double precision default null,p_lng double precision default null)returns jsonb language plpgsql security definer set search_path=''as $$
declare actor text:=app_private.verified_phone();r jsonb;existing uuid;begin
 if(p_lat is null)<>(p_lng is null)or(p_lat is not null and(not(p_lat between -90 and 90)or not(p_lng between -180 and 180)))then raise exception 'Invalid coordinates';end if;
 perform pg_advisory_xact_lock(hashtextextended(actor||coalesce(p_client_id::text,''),0));
 select id into existing from public.service_orders where customer_phone=actor and client_request_id=p_client_id;
 if existing is not null then return jsonb_build_object('ok',true,'id',existing);end if;
 r:=app_private.create_service_order_v432(p_ad_id,p_description,p_address,p_from,p_to,p_client_id);
 update public.service_orders set location_lat=p_lat,location_lng=p_lng where id=(r->>'id')::uuid and customer_phone=actor;
 return r;end$$;
create function public.create_service_order_v439(p_ad_id uuid,p_description text,p_address text,p_from timestamptz,p_to timestamptz,p_client_id uuid,p_lat double precision default null,p_lng double precision default null)returns jsonb language sql security invoker set search_path=''as $$select app_private.create_service_order_v439(p_ad_id,p_description,p_address,p_from,p_to,p_client_id,p_lat,p_lng)$$;
create function app_private.district_people_v439(p_query text default '',p_after text default null,p_chat_id uuid default null)returns jsonb language plpgsql security definer set search_path=''as $$
declare actor text:=app_private.verified_phone();me public.profiles%rowtype;digits text:=regexp_replace(coalesce(p_query,''),'\D','','g');q text:=left(trim(coalesce(p_query,'')),100);r jsonb;begin
 select *into me from public.profiles where phone=actor;if me.city is null or me.district is null then raise exception 'ჯერ პროფილში აირჩიე ქალაქი და რაიონი.'using errcode='42501';end if;
 if left(digits,5)='00995'then digits:=substring(digits from 6);elsif left(digits,3)='995'and length(digits)>9 then digits:=substring(digits from 4);end if;
 if length(digits)=10 and left(digits,1)='0'then digits:=substring(digits from 2);end if;
 if p_chat_id is not null and not exists(select 1 from public.live_chat_members where chat_id=p_chat_id and phone=actor and role in('owner','admin'))then raise exception 'Group admin required'using errcode='42501';end if;
 select coalesce(jsonb_agg(to_jsonb(x)order by x.phone),'[]')into r from(select p.phone,p.full_name,p.city,p.district,p.neighborhood,p.avatar_url,exists(select 1 from public.live_chat_members m where m.chat_id=p_chat_id and m.phone=p.phone)already_member from public.profiles p where p.city=me.city and p.district=me.district and p.phone<>actor and not public.is_user_blocked(actor,p.phone)
 and(p_after is null or p.phone>p_after)and(q=''or(length(digits)between 3 and 9 and left(p.phone,length(digits))=digits)or(digits=''and length(q)>=2 and position(lower(q)in lower(coalesce(p.full_name,'')))>0))order by p.phone limit 51)x;
 return jsonb_build_object('items',case when jsonb_array_length(r)>50 then r-50 else r end,'has_more',jsonb_array_length(r)>50);end$$;
create function public.district_people_v439(p_query text default '',p_after text default null,p_chat_id uuid default null)returns jsonb language sql security invoker set search_path=''as $$select app_private.district_people_v439(p_query,p_after,p_chat_id)$$;
create table app_private.campaign_batches_v439(id uuid primary key,actor text not null,payload jsonb not null,result jsonb,created_at timestamptz not null default now());
alter table app_private.campaign_batches_v439 enable row level security;revoke all on app_private.campaign_batches_v439 from public,anon,authenticated;
create function app_private.publish_campaign_batch_v439(p_data jsonb,p_client_id uuid)returns jsonb language plpgsql security definer set search_path=''as $$
declare actor text:=app_private.verified_phone();saved app_private.campaign_batches_v439%rowtype;t jsonb;ds text[];c text;n text;r jsonb;ids jsonb:='[]';idx integer:=0;begin
 if length(trim(coalesce(p_data->>'title','')))not between 1 and 160 or length(trim(coalesce(p_data->>'body','')))not between 1 and 5000 then raise exception 'შეავსე სათაური და ტექსტი.';end if;
 if p_client_id is null or jsonb_typeof(p_data->'audience')is distinct from 'array'or jsonb_array_length(p_data->'audience')not between 1 and 256 then raise exception 'აირჩიე გავრცელების ადგილები.';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_client_id::text,439));select *into saved from app_private.campaign_batches_v439 where id=p_client_id;
 if found then if saved.actor<>actor or saved.payload<>p_data then raise exception 'Request conflict'using errcode='42501';end if;return saved.result;end if;
 -- Validate the whole batch before publishing any segment.
 for t in select value from jsonb_array_elements(p_data->'audience')loop
 c:=t->>'city';n:=nullif(t->>'neighborhood','');select array_agg(distinct value)into ds from jsonb_array_elements_text(t->'districts');
 if coalesce(cardinality(ds),0)=0 or exists(select 1 from unnest(ds)d where not exists(select 1 from app_private.location_catalog l where l.city=c and l.district=d and(n is null or l.neighborhoods?n)))or(n is not null and cardinality(ds)<>1)then raise exception 'Invalid audience';end if;
 if not app_private.staff_can_v433('campaigns',c,ds)then raise exception 'ამ არეალში გამოქვეყნების უფლება არ გაქვს.'using errcode='42501';end if;
 end loop;
 insert into app_private.campaign_batches_v439(id,actor,payload)values(p_client_id,actor,p_data);
 for t in select value from jsonb_array_elements(p_data->'audience')loop
 idx:=idx+1;r:=app_private.publish_staff_campaign_v433((p_data-'audience')||t,md5(p_client_id::text||':'||idx)::uuid);ids:=ids||jsonb_build_array(r->>'id');
 end loop;
 r:=jsonb_build_object('ok',true,'ids',ids);update app_private.campaign_batches_v439 set result=r where id=p_client_id;return r;end$$;
create function public.publish_campaign_batch_v439(p_data jsonb,p_client_id uuid)returns jsonb language sql security invoker set search_path=''as $$select app_private.publish_campaign_batch_v439(p_data,p_client_id)$$;
revoke all on function app_private.create_service_order_v439(uuid,text,text,timestamptz,timestamptz,uuid,double precision,double precision),public.create_service_order_v439(uuid,text,text,timestamptz,timestamptz,uuid,double precision,double precision),app_private.district_people_v439(text,text,uuid),public.district_people_v439(text,text,uuid),app_private.publish_campaign_batch_v439(jsonb,uuid),public.publish_campaign_batch_v439(jsonb,uuid)from public,anon;
grant execute on function app_private.create_service_order_v439(uuid,text,text,timestamptz,timestamptz,uuid,double precision,double precision),public.create_service_order_v439(uuid,text,text,timestamptz,timestamptz,uuid,double precision,double precision),app_private.district_people_v439(text,text,uuid),public.district_people_v439(text,text,uuid),app_private.publish_campaign_batch_v439(jsonb,uuid),public.publish_campaign_batch_v439(jsonb,uuid)to authenticated;
notify pgrst,'reload schema';

alter table public.specialist_announcements add column target_neighborhood text;
create table app_private.service_batches_v439(like app_private.campaign_batches_v439 including all);
alter table app_private.service_batches_v439 enable row level security;revoke all on app_private.service_batches_v439 from public,anon,authenticated;
create function app_private.submit_specialist_batch_v439(p_data jsonb,p_client_id uuid)returns jsonb language plpgsql security definer set search_path=''as $$
declare actor text:=app_private.verified_phone();saved app_private.service_batches_v439%rowtype;t jsonb;ds text[];c text;n text;r jsonb;ids jsonb:='[]';idx integer:=0;begin
 if p_client_id is null or jsonb_typeof(p_data->'audience')is distinct from 'array'or jsonb_array_length(p_data->'audience')not between 1 and 256 then raise exception 'აირჩიე გავრცელების ადგილები.';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_client_id::text,439));select *into saved from app_private.service_batches_v439 where id=p_client_id;
 if found then if saved.actor<>actor or saved.payload<>p_data then raise exception 'Request conflict'using errcode='42501';end if;return saved.result;end if;
 -- Validate the whole batch before publishing any segment.
 for t in select value from jsonb_array_elements(p_data->'audience')loop
 c:=t->>'city';n:=nullif(t->>'neighborhood','');select array_agg(distinct value)into ds from jsonb_array_elements_text(t->'districts');
 if coalesce(cardinality(ds),0)=0 or exists(select 1 from unnest(ds)d where not exists(select 1 from app_private.location_catalog l where l.city=c and l.district=d and(n is null or l.neighborhoods?n)))or(n is not null and cardinality(ds)<>1)then raise exception 'Invalid audience';end if;

 end loop;
 insert into app_private.service_batches_v439(id,actor,payload)values(p_client_id,actor,p_data);
 for t in select value from jsonb_array_elements(p_data->'audience')loop
 idx:=idx+1;r:=app_private.submit_specialist_v432((p_data-'audience')||t,md5(p_client_id::text||':'||idx)::uuid);update public.specialist_announcements set target_neighborhood=nullif(t->>'neighborhood','')where id=(r->>'id')::uuid and owner_phone=actor;ids:=ids||jsonb_build_array(r->>'id');
 end loop;
 r:=jsonb_build_object('ok',true,'ids',ids);update app_private.service_batches_v439 set result=r where id=p_client_id;return r;end$$;
create function public.submit_specialist_batch_v439(p_data jsonb,p_client_id uuid)returns jsonb language sql security invoker set search_path=''as $$select app_private.submit_specialist_batch_v439(p_data,p_client_id)$$;
revoke all on function app_private.submit_specialist_batch_v439(jsonb,uuid),public.submit_specialist_batch_v439(jsonb,uuid)from public,anon;
grant execute on function app_private.submit_specialist_batch_v439(jsonb,uuid),public.submit_specialist_batch_v439(jsonb,uuid)to authenticated;
create or replace function app_private.specialist_ads_v432(p_scope text default 'public')returns jsonb language plpgsql security definer set search_path=''as $$
declare actor text:=app_private.verified_phone();me public.profiles%rowtype;r jsonb;begin
 select * into me from public.profiles where phone=actor;
 if p_scope is null or p_scope not in('public','mine','admin')then raise exception 'Invalid scope';end if;
 if p_scope='admin'and not(coalesce(me.is_super_admin,false)or coalesce(me.admin_level='super',false))then raise exception 'Admin required'using errcode='42501';end if;
 select coalesce(jsonb_agg((to_jsonb(x)-'owner_phone'-'contact_phone'-'client_request_id')order by x.created_at desc),'[]')into r from(
 select a.*,coalesce(v.rating_count,0)rating_count,v.rating_average from public.specialist_announcements a
 left join lateral(select count(*)rating_count,round(avg(r.rating)::numeric,1)rating_average from public.service_order_reviews r where r.provider_phone=a.owner_phone and r.rating between 1 and 5)v on true
 where case p_scope when 'mine'then a.owner_phone=actor when 'admin'then true else a.status='approved'and(me.is_super_admin or me.admin_level='super'or(a.city=me.city and me.district=any(a.target_districts)and(a.target_neighborhood is null or a.target_neighborhood=me.neighborhood)))end
 and(p_scope<>'public'or not public.is_user_blocked(actor,a.owner_phone))order by a.created_at desc limit 100)x;return r;end$$;

notify pgrst,'reload schema';

-- Public content can target multiple catalog locations. Existing rows keep their original scope.
alter table public.posts add column audience jsonb;
alter table public.marketplace_listings add column audience jsonb;
create function app_private.audience_matches_v439(a jsonb,c text,d text,n text)returns boolean language sql immutable set search_path=''as $$
 select exists(select 1 from jsonb_array_elements(a)t where t->>'city'=c and (t->'districts')?d and(nullif(t->>'neighborhood','')is null or t->>'neighborhood'=n))$$;
revoke all on function app_private.audience_matches_v439(jsonb,text,text,text)from public,anon;
grant execute on function app_private.audience_matches_v439(jsonb,text,text,text)to authenticated;
create table app_private.content_requests_v439(like app_private.campaign_batches_v439 including all);
alter table app_private.content_requests_v439 enable row level security;revoke all on app_private.content_requests_v439 from public,anon,authenticated;
create function app_private.publish_content_v439(p_kind text,p_data jsonb,p_client_id uuid)returns jsonb language plpgsql security definer set search_path=''as $$
declare actor text:=app_private.verified_phone();saved app_private.content_requests_v439%rowtype;t jsonb;ds text[];c text;n text;r jsonb;payload jsonb:=jsonb_build_object('kind',p_kind,'data',p_data);begin
 if p_kind is null or p_kind not in('post','market')or p_client_id is null or jsonb_typeof(p_data->'audience')is distinct from 'array'or jsonb_array_length(p_data->'audience')not between 1 and 256 then raise exception 'Invalid publication';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_client_id::text,439));select *into saved from app_private.content_requests_v439 where id=p_client_id;
 if found then if saved.actor<>actor or saved.payload<>payload then raise exception 'Request conflict'using errcode='42501';end if;return saved.result;end if;
 for t in select value from jsonb_array_elements(p_data->'audience')loop
 c:=t->>'city';n:=nullif(t->>'neighborhood','');select array_agg(distinct value)into ds from jsonb_array_elements_text(t->'districts');
 if coalesce(cardinality(ds),0)=0 or exists(select 1 from unnest(ds)d where not exists(select 1 from app_private.location_catalog l where l.city=c and l.district=d and(n is null or l.neighborhoods?n)))or(n is not null and cardinality(ds)<>1)then raise exception 'Invalid audience';end if;
 end loop;
 if p_kind='post'then
 r:=public.create_post(actor,coalesce(nullif(p_data->>'type',''),'პოსტი'),p_data->>'content',p_data->>'image_url');
 if r->>'id'is null then raise exception 'Publication failed';end if;
 update public.posts set audience=p_data->'audience'where id=(r->>'id')::uuid and author_phone=actor;
 else
 if coalesce((p_data->>'price')::numeric,0)<0 or lower(coalesce(p_data->>'price','0'))in('nan','infinity','-infinity')then raise exception 'Invalid price';end if;
 r:=public.create_marketplace_listing(actor,p_data->>'title',p_data->>'description',p_data->>'category',coalesce((p_data->>'price')::numeric,0),p_data->>'image_url');
 if r->>'id'is null then raise exception 'Publication failed';end if;
 update public.marketplace_listings set audience=p_data->'audience'where id=(r->>'id')::uuid and owner_phone=actor;
 end if;
 insert into app_private.content_requests_v439(id,actor,payload,result)values(p_client_id,actor,payload,r);return r;end$$;
create function public.publish_content_v439(p_kind text,p_data jsonb,p_client_id uuid)returns jsonb language sql security invoker set search_path=''as $$select app_private.publish_content_v439(p_kind,p_data,p_client_id)$$;
revoke all on function app_private.publish_content_v439(text,jsonb,uuid),public.publish_content_v439(text,jsonb,uuid)from public,anon;
grant execute on function app_private.publish_content_v439(text,jsonb,uuid),public.publish_content_v439(text,jsonb,uuid)to authenticated;

create or replace function public.search_feed(p_query text default '',p_before timestamptz default null,p_before_id uuid default null)returns jsonb language plpgsql security definer set search_path='' as $$
declare actor text:=app_private.verified_phone();r jsonb;q text:=btrim(coalesce(p_query,''));begin
 if length(q)>100 then raise exception 'Search is too long';end if;
 select coalesce(jsonb_agg(to_jsonb(x)order by x.created_at desc,x.id desc),'[]'::jsonb)into r from(
 select p.*,(select count(*)from public.post_likes l where l.post_id=p.id)like_count,(select count(*)from public.post_comments c where c.post_id=p.id)comment_count,exists(select 1 from public.post_likes l where l.post_id=p.id and l.phone=actor)liked
 from public.posts p join public.profiles me on me.phone=actor join public.profiles author on author.phone=p.author_phone
 where(me.is_super_admin or me.admin_level='super'or case when p.audience is null then (p.district=me.district and author.city is not distinct from me.city)else app_private.audience_matches_v439(p.audience,me.city,me.district,me.neighborhood)end)
 and not exists(select 1 from public.user_blocks b where(b.blocker_phone=actor and b.blocked_phone=p.author_phone)or(b.blocker_phone=p.author_phone and b.blocked_phone=actor))
 and(q=''or position(lower(q)in lower(coalesce(p.content,'')||' '||coalesce(p.author_name,'')))>0)
 and(p_before is null or(p.created_at,p.id)<(p_before,p_before_id))order by p.created_at desc,p.id desc limit 25)x;return r;end $$;

create or replace function app_private.post_target(p_id uuid)returns jsonb language plpgsql security definer set search_path='' as $$declare actor text:=app_private.verified_phone();result jsonb;begin
 select to_jsonb(p)||jsonb_build_object('like_count',(select count(*)from public.post_likes where post_id=p.id),'comment_count',(select count(*)from public.post_comments where post_id=p.id),'liked',exists(select 1 from public.post_likes where post_id=p.id and phone=actor))into result
 from public.posts p join public.profiles me on me.phone=actor join public.profiles author on author.phone=p.author_phone
 where p.id=p_id and(me.is_super_admin or me.admin_level='super'or case when p.audience is null then (p.district=me.district and author.city is not distinct from me.city)else app_private.audience_matches_v439(p.audience,me.city,me.district,me.neighborhood)end)and not exists(select 1 from public.user_blocks b where(b.blocker_phone=actor and b.blocked_phone=p.author_phone)or(b.blocker_phone=p.author_phone and b.blocked_phone=actor));return result;end$$;

CREATE OR REPLACE FUNCTION app_private.legacy_list_marketplace(p_phone text)
 RETURNS TABLE(id uuid, owner_phone text, owner_name text, district text, neighborhood text, title text, description text, category text, price numeric, image_url text, status text, created_at timestamp with time zone)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select m.id,m.owner_phone,m.owner_name,m.district,m.neighborhood,m.title,m.description,m.category,m.price,m.image_url,m.status,m.created_at
 from public.marketplace_listings m
 where m.status='active' and m.created_at>now()-interval '30 days' and (m.audience is null or m.owner_phone=app_private.verified_phone() or exists(select 1 from public.profiles me where me.phone=app_private.verified_phone() and app_private.audience_matches_v439(m.audience,me.city,me.district,me.neighborhood)))
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
  where m.owner_phone=v_target and m.status='active' and m.created_at>now()-interval '30 days' and (m.audience is null or m.owner_phone=app_private.verified_phone() or exists(select 1 from public.profiles me where me.phone=app_private.verified_phone() and app_private.audience_matches_v439(m.audience,me.city,me.district,me.neighborhood)))
  order by m.created_at desc
  limit 200;
end $function$;
notify pgrst,'reload schema';

-- Erase new retry ledgers along with the account.
alter table app_private.campaign_batches_v439 add constraint campaign_batches_v439_actor_fk foreign key(actor)references public.profiles(phone)on delete cascade;
alter table app_private.service_batches_v439 add constraint service_batches_v439_actor_fk foreign key(actor)references public.profiles(phone)on delete cascade;
alter table app_private.content_requests_v439 add constraint content_requests_v439_actor_fk foreign key(actor)references public.profiles(phone)on delete cascade;
