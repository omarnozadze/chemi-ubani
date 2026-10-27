begin;
create table if not exists public.admin_campaigns(
 id uuid primary key default gen_random_uuid(),client_id uuid not null unique,
 author_phone text not null,title text not null check(length(title) between 1 and 160),body text not null check(length(body) between 1 and 5000),
 category text not null,placement text not null,city text not null,target_districts text[] not null,neighborhood text,
 image_url text,status text not null default 'active' check(status in('active','paused','deleted')),
 created_at timestamptz not null default now(),expires_at timestamptz not null
);
alter table public.admin_campaigns enable row level security;
revoke all on public.admin_campaigns from public,anon,authenticated;
alter table public.hot_news add column if not exists city text;
alter table public.hot_news add column if not exists neighborhood text;
alter table public.hot_news add column if not exists campaign_id uuid references public.admin_campaigns(id);
alter table public.hot_news add column if not exists image_url text;
alter table public.hot_news add column if not exists expires_at timestamptz;
create or replace function public.publish_admin_campaign(p_data jsonb,p_client_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor text:=app_private.verified_phone();item public.admin_campaigns%rowtype;district_name text;news_id uuid;peer record;targets text[];days integer;place text;
begin
 if not exists(select 1 from public.profiles where phone=actor and (is_super_admin or admin_level='super')) then raise exception 'Administrator required' using errcode='42501';end if;
 if p_client_id is null then raise exception 'Request ID required';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_client_id::text,0));
 select * into item from public.admin_campaigns where client_id=p_client_id;
 if found then return jsonb_build_object('ok',true,'id',item.id);end if;
 select array_agg(distinct trim(x)) into targets from jsonb_array_elements_text(p_data->'districts')x where trim(x)<>'';
 days=(p_data->>'days')::integer;place=p_data->>'placement';
 if coalesce(cardinality(targets),0)=0 or cardinality(targets)>100 or days is null or days<1 or days>365 or nullif(trim(p_data->>'city'),'')is null then raise exception 'Select location and duration';end if;
 if place is null or place not in('საწყისი Full Screen','Feed რეკლამა','Push Notification','Full Screen + Push','ცხელი ამბები','ცხელი ამბები + Push')then raise exception 'Invalid placement';end if;
 if nullif(p_data->>'image','') is not null and (p_data->>'image')!~'^https://' then raise exception 'Invalid image URL';end if;
 if nullif(p_data->>'neighborhood','')is not null and cardinality(targets)<>1 then raise exception 'One district required for a neighborhood';end if;
 insert into public.admin_campaigns(client_id,author_phone,title,body,category,placement,city,target_districts,neighborhood,image_url,expires_at)
 values(p_client_id,actor,trim(p_data->>'title'),trim(p_data->>'body'),coalesce(p_data->>'category','რეკლამა'),place,trim(p_data->>'city'),targets,nullif(p_data->>'neighborhood',''),nullif(p_data->>'image',''),now()+make_interval(days=>days))returning * into item;
 if place like '%ცხელი ამბები%' or place like '%Push%' then
  foreach district_name in array targets loop
   insert into public.hot_news(author_phone,title,body,category,district,city,neighborhood,campaign_id,image_url,expires_at)
   values(actor,item.title,item.body,case when item.category in('მნიშვნელოვანი','ტრენდი')then item.category else 'რეკლამა'end,district_name,item.city,item.neighborhood,item.id,item.image_url,item.expires_at)returning id into news_id;
   for peer in select p.phone from public.profiles p where p.city=item.city and p.district=district_name and(item.neighborhood is null or p.neighborhood=item.neighborhood) loop
    perform app_private.emit_activity(peer.phone,actor,'hot_news','ახალი ცხელი ამბავი შენს რაიონში','hot:'||news_id);
   end loop;
  end loop;
 end if;
 return jsonb_build_object('ok',true,'id',item.id);
end $$;
create or replace function public.list_admin_campaigns()
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor text:=app_private.verified_phone();result jsonb;
begin
 select coalesce(jsonb_agg(to_jsonb(x)order by x.created_at desc),'[]'::jsonb)into result from(
 select c.id,c.title,c.body,c.category,c.placement,c.city,c.target_districts,c.neighborhood,c.image_url,c.status,c.created_at,c.expires_at from public.admin_campaigns c join public.profiles p on p.phone=actor
 where c.status<>'deleted' and ((p.is_super_admin or p.admin_level='super')or(c.status='active'and c.expires_at>now()and c.city=p.city and p.district=any(c.target_districts)and(c.neighborhood is null or c.neighborhood=p.neighborhood)))
 order by c.created_at desc limit 100)x;return result;
end $$;
create or replace function public.update_admin_campaign(p_id uuid,p_status text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor text:=app_private.verified_phone();begin
 if not exists(select 1 from public.profiles where phone=actor and(is_super_admin or admin_level='super'))then raise exception 'Administrator required'using errcode='42501';end if;
 if p_status is null or p_status not in('active','paused','deleted')then raise exception 'Invalid status';end if;
 update public.admin_campaigns set status=p_status where id=p_id and status<>'deleted';
 if not found then raise exception 'Campaign not found';end if;return jsonb_build_object('ok',true);
end $$;
create or replace function app_private.list_hot_news()
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor text:=app_private.verified_phone();result jsonb;begin
 select coalesce(jsonb_agg(to_jsonb(x)order by x.created_at desc),'[]'::jsonb)into result from(
 select h.id,h.title,h.body,h.category,h.district,h.city,h.neighborhood,h.image_url,h.created_at from public.hot_news h
 join public.profiles p on p.phone=actor left join public.admin_campaigns c on c.id=h.campaign_id
 where(h.expires_at is null or h.expires_at>now())and(h.campaign_id is null or c.status='active')
 and ((p.is_super_admin or p.admin_level='super')or(h.district=p.district and(h.city is null or h.city=p.city)and(h.neighborhood is null or h.neighborhood=p.neighborhood)))
 order by h.created_at desc limit 100)x;return result;end $$;
revoke all on function public.publish_admin_campaign(jsonb,uuid),public.list_admin_campaigns(),public.update_admin_campaign(uuid,text)from public,anon;
grant execute on function public.publish_admin_campaign(jsonb,uuid),public.list_admin_campaigns(),public.update_admin_campaign(uuid,text)to authenticated;
notify pgrst,'reload schema';
commit;
