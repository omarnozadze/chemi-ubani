-- Explicit assignments cannot move when a staff member edits their own profile location.
create table app_private.staff_scope_v433(phone text primary key,role text not null check(role in('district','moderator')),city text not null,district text not null);
alter table app_private.staff_scope_v433 enable row level security;
revoke all on app_private.staff_scope_v433 from public,anon,authenticated;
insert into app_private.staff_scope_v433 select phone,case when admin_level='moderator'then 'moderator'else 'district'end,city,district from public.profiles where admin_level in('district_admin','moderator')and city is not null and district is not null;
alter table public.posts add column if not exists pinned boolean not null default false;
create table app_private.moderation_audit_v433(id bigint generated always as identity primary key,actor text not null,kind text not null,target uuid,action text not null,created_at timestamptz not null default now());
alter table app_private.moderation_audit_v433 enable row level security;
revoke all on app_private.moderation_audit_v433 from public,anon,authenticated;
create function app_private.staff_can_v433(kind text,city_name text,areas text[])returns boolean language plpgsql security definer set search_path=''as $$declare actor text:=app_private.verified_phone();s app_private.staff_scope_v433%rowtype;begin
 if exists(select 1 from public.profiles where phone=actor and(is_super_admin or admin_level='super'))then return true;end if;
 select * into s from app_private.staff_scope_v433 where phone=actor;
 return coalesce(s.city=city_name and areas=array[s.district]and(s.role='district'or(s.role='moderator'and kind='posts')),false);
end$$;
revoke all on function app_private.staff_can_v433(text,text,text[])from public,anon,authenticated;
-- Older privileged endpoints remain superadmin-only; delegated rights use scoped APIs below.
create or replace function app_private.require_admin()returns void language plpgsql security definer set search_path=''as $$begin
 if not exists(select 1 from public.profiles where phone=app_private.verified_phone()and(is_super_admin or admin_level='super'))then raise exception 'Superadmin required'using errcode='42501';end if;end$$;
create function app_private.staff_info_v433()returns jsonb language plpgsql security definer set search_path=''as $$declare actor text:=app_private.verified_phone();s app_private.staff_scope_v433%rowtype;begin
 if exists(select 1 from public.profiles where phone=actor and(is_super_admin or admin_level='super'))then return jsonb_build_object('role','super');end if;
 select * into s from app_private.staff_scope_v433 where phone=actor;return jsonb_build_object('role',coalesce(s.role,'user'),'city',s.city,'district',s.district);end$$;
create function public.staff_info_v433()returns jsonb language sql security invoker set search_path=''as $$select app_private.staff_info_v433()$$;
create function app_private.assign_staff_v433(p_phone text,p_role text,p_city text,p_district text)returns jsonb language plpgsql security definer set search_path=''as $$begin
 perform app_private.require_admin();
 if p_role not in('user','district','moderator')or p_role is null then raise exception 'Invalid role';end if;
 perform 1 from public.profiles where phone=p_phone and not coalesce(is_super_admin,false)and admin_level is distinct from 'super'for update;if not found then raise exception 'Target unavailable';end if;
 if p_role<>'user'and not exists(select 1 from app_private.location_catalog where city=p_city and district=p_district)then raise exception 'Invalid location';end if;
 delete from app_private.staff_scope_v433 where phone=p_phone;
 if p_role<>'user'then insert into app_private.staff_scope_v433 values(p_phone,p_role,p_city,p_district);end if;
 update public.profiles set admin_level=case p_role when 'district'then 'district_admin'else p_role end where phone=p_phone;
 insert into app_private.moderation_audit_v433(actor,kind,action)values(app_private.verified_phone(),'staff','assign:'||p_role);return jsonb_build_object('ok',true);end$$;
create function public.assign_staff_v433(p_phone text,p_role text,p_city text,p_district text)returns jsonb language sql security invoker set search_path=''as $$select app_private.assign_staff_v433(p_phone,p_role,p_city,p_district)$$;
create function app_private.manage_list_v433(p_kind text,p_before timestamptz default null,p_before_id uuid default null)returns jsonb language plpgsql security definer set search_path=''as $$declare r jsonb;begin
 perform app_private.verified_phone();
 if p_kind not in('posts','news','services','campaigns','banners')then raise exception 'Invalid category';end if;
 with items as(
 select p.id,p.created_at,coalesce(a.city,'')city,array[p.district]areas,jsonb_build_object('id',p.id,'title',p.author_name,'body',p.content,'image',p.image_url,'pinned',p.pinned,'created_at',p.created_at,'city',a.city,'areas',array[p.district])data from public.posts p left join public.profiles a on a.phone=p.author_phone where p_kind='posts'
 union all select h.id,h.created_at,h.city,array[h.district],jsonb_build_object('id',h.id,'title',h.title,'body',h.body,'image',h.image_url,'created_at',h.created_at,'city',h.city,'areas',array[h.district],'campaign_id',h.campaign_id)from public.hot_news h where p_kind='news'and h.campaign_id is null
 union all select s.id,s.created_at,s.city,s.target_districts,jsonb_build_object('id',s.id,'title',s.title,'body',s.body,'image',s.image_url,'status',s.status,'created_at',s.created_at,'city',s.city,'areas',s.target_districts)from public.specialist_announcements s where p_kind='services'
 union all select c.id,c.created_at,c.city,c.target_districts,jsonb_build_object('id',c.id,'title',c.title,'body',c.body,'image',c.image_url,'status',c.status,'placement',c.placement,'created_at',c.created_at,'expires_at',c.expires_at,'city',c.city,'areas',c.target_districts)from public.admin_campaigns c where p_kind='campaigns'and c.status<>'deleted'
 union all select b.id,b.created_at,p.city,array[p.district],jsonb_build_object('id',b.id,'title',coalesce(b.title,x.name),'body',x.name,'image',b.image_url,'status',case when b.active then 'active'else 'inactive'end,'created_at',b.created_at,'city',p.city,'areas',array[p.district])from public.business_banners b join public.businesses x on x.id=b.business_id join public.profiles p on p.phone=x.owner_phone where p_kind='banners'
 )select coalesce(jsonb_agg(data order by created_at desc,id desc),'[]'::jsonb)into r from(select *from items where app_private.staff_can_v433(p_kind,city,areas)and(p_before is null or(created_at,id)<(p_before,p_before_id))order by created_at desc,id desc limit 30)x;return r;
end$$;
create function public.manage_list_v433(p_kind text,p_before timestamptz default null,p_before_id uuid default null)returns jsonb language sql security invoker set search_path=''as $$select app_private.manage_list_v433(p_kind,p_before,p_before_id)$$;
create function app_private.manage_action_v433(p_kind text,p_id uuid,p_action text,p_data jsonb default '{}'::jsonb)returns jsonb language plpgsql security definer set search_path=''as $$declare city_name text;areas text[];actor text:=app_private.verified_phone();role_name text;old_data jsonb;begin
 role_name:=app_private.staff_info_v433()->>'role';
 if p_kind='posts'then select a.city,array[p.district],jsonb_build_object('body',p.content,'pinned',p.pinned)into city_name,areas,old_data from public.posts p left join public.profiles a on a.phone=p.author_phone where p.id=p_id for update of p;
 elsif p_kind='news'then select h.city,array[h.district],jsonb_build_object('title',h.title,'body',h.body)into city_name,areas,old_data from public.hot_news h where h.id=p_id and h.campaign_id is null for update;
 elsif p_kind='services'then select s.city,s.target_districts,jsonb_build_object('title',s.title,'body',s.body,'status',s.status)into city_name,areas,old_data from public.specialist_announcements s where s.id=p_id for update;
 elsif p_kind='campaigns'then select c.city,c.target_districts,jsonb_build_object('title',c.title,'body',c.body,'status',c.status)into city_name,areas,old_data from public.admin_campaigns c where c.id=p_id and c.status<>'deleted'for update;
 elsif p_kind='banners'then select p.city,array[p.district],jsonb_build_object('title',b.title)into city_name,areas,old_data from public.business_banners b join public.businesses x on x.id=b.business_id join public.profiles p on p.phone=x.owner_phone where b.id=p_id for update of b;
 else raise exception 'Invalid category';end if;
 if old_data is null or not app_private.staff_can_v433(p_kind,city_name,areas)then raise exception 'წვდომა არ გაქვს ან ჩანაწერი აღარ არსებობს'using errcode='42501';end if;
 if role_name='moderator'and(p_kind<>'posts'or p_action not in('edit','pin'))then raise exception 'Moderator may edit or pin posts only'using errcode='42501';end if;
 if p_data?'expected'and p_data->'expected'<>old_data then return jsonb_build_object('ok',false,'code','conflict');end if;
 if p_action='edit'then
 if p_kind='banners'or length(trim(coalesce(p_data->>'body','')))not between 1 and 5000 then raise exception 'ტექსტი უნდა იყოს 1–5000 სიმბოლო';end if;
 if p_kind<>'posts'and length(trim(coalesce(p_data->>'title','')))not between 1 and 160 then raise exception 'სათაური უნდა იყოს 1–160 სიმბოლო';end if;
 if p_kind='services'and app_private.has_external_contact_v432(coalesce(p_data->>'body','')||' '||coalesce(p_data->>'title',''))then raise exception 'გარე კონტაქტის გაზიარება დაუშვებელია';end if;
 if p_kind='posts'then update public.posts set content=trim(p_data->>'body')where id=p_id;
 elsif p_kind='news'then update public.hot_news set title=trim(p_data->>'title'),body=trim(p_data->>'body')where id=p_id;
 elsif p_kind='services'then update public.specialist_announcements set title=trim(p_data->>'title'),body=trim(p_data->>'body')where id=p_id;
 elsif p_kind='campaigns'then update public.admin_campaigns set title=trim(p_data->>'title'),body=trim(p_data->>'body'),revision=revision+1 where id=p_id;update public.hot_news set title=trim(p_data->>'title'),body=trim(p_data->>'body')where campaign_id=p_id;end if;
 elsif p_action='pin'and p_kind='posts'then update public.posts set pinned=coalesce((p_data->>'pinned')::boolean,false)where id=p_id;
 elsif p_action='delete'and p_kind in('posts','news','banners','campaigns')then
 if p_kind='posts'then delete from public.posts where id=p_id;
 elsif p_kind='news'then delete from public.hot_news where id=p_id;
 elsif p_kind='banners'then delete from public.business_banners where id=p_id;
 else update public.admin_campaigns set status='deleted',revision=revision+1 where id=p_id;end if;
 elsif p_action in('approve','reject')and p_kind='services'then
 if p_action='reject'and length(trim(coalesce(p_data->>'reason','')))<3 then raise exception 'მიუთითე უარყოფის მიზეზი';end if;
 update public.specialist_announcements set status=case p_action when 'approve'then 'approved'else 'rejected'end,review_note=case when p_action='reject'then trim(p_data->>'reason')else null end,reviewed_by=actor,reviewed_at=now()where id=p_id;
 else raise exception 'მოქმედება დაუშვებელია';end if;
 insert into app_private.moderation_audit_v433(actor,kind,target,action)values(actor,p_kind,p_id,p_action);return jsonb_build_object('ok',true);
end$$;
create function public.manage_action_v433(p_kind text,p_id uuid,p_action text,p_data jsonb default '{}'::jsonb)returns jsonb language sql security invoker set search_path=''as $$select app_private.manage_action_v433(p_kind,p_id,p_action,p_data)$$;
create function app_private.feed_pins_v433()returns jsonb language plpgsql security definer set search_path=''as $$declare actor text:=app_private.verified_phone();r jsonb;begin
 select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb)into r from(select p.id,p.author_name,p.content,p.image_url,p.district,p.created_at from public.posts p join public.profiles a on a.phone=p.author_phone join public.profiles me on me.phone=actor where p.pinned and(p.district=me.district and a.city=me.city)and not exists(select 1 from public.user_blocks b where(b.blocker_phone=actor and b.blocked_phone=p.author_phone)or(b.blocker_phone=p.author_phone and b.blocked_phone=actor))order by p.created_at desc,p.id desc limit 5)x;return r;end$$;
create function public.feed_pins_v433()returns jsonb language sql security invoker set search_path=''as $$select app_private.feed_pins_v433()$$;
revoke all on function app_private.staff_info_v433(),public.staff_info_v433(),app_private.assign_staff_v433(text,text,text,text),public.assign_staff_v433(text,text,text,text),app_private.manage_list_v433(text,timestamptz,uuid),public.manage_list_v433(text,timestamptz,uuid),app_private.manage_action_v433(text,uuid,text,jsonb),public.manage_action_v433(text,uuid,text,jsonb),app_private.feed_pins_v433(),public.feed_pins_v433()from public,anon;
grant execute on function app_private.staff_info_v433(),public.staff_info_v433(),app_private.assign_staff_v433(text,text,text,text),public.assign_staff_v433(text,text,text,text),app_private.manage_list_v433(text,timestamptz,uuid),public.manage_list_v433(text,timestamptz,uuid),app_private.manage_action_v433(text,uuid,text,jsonb),public.manage_action_v433(text,uuid,text,jsonb),app_private.feed_pins_v433(),public.feed_pins_v433()to authenticated;
create or replace function app_private.publish_staff_campaign_v433(p_data jsonb,p_client_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor text:=app_private.verified_phone();item public.admin_campaigns%rowtype;district_name text;news_id uuid;peer record;targets text[];days integer;place text;
begin
 if not app_private.staff_can_v433('campaigns',p_data->>'city',array(select jsonb_array_elements_text(p_data->'districts')))then raise exception 'Campaign outside assigned district'using errcode='42501';end if;
 if p_client_id is null then raise exception 'Request ID required';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_client_id::text,0));
 select * into item from public.admin_campaigns where client_id=p_client_id;
 if found and item.author_phone<>actor then raise exception 'Request unavailable'using errcode='42501';end if;
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

create function public.publish_staff_campaign_v433(p_data jsonb,p_client_id uuid)returns jsonb language sql security invoker set search_path=''as $$select app_private.publish_staff_campaign_v433(p_data,p_client_id)$$;
revoke all on function public.publish_staff_campaign_v433(jsonb,uuid),app_private.publish_staff_campaign_v433(jsonb,uuid)from public,anon;
grant execute on function public.publish_staff_campaign_v433(jsonb,uuid),app_private.publish_staff_campaign_v433(jsonb,uuid)to authenticated;
notify pgrst,'reload schema';
alter table public.business_banners add column if not exists client_id uuid;
create unique index if not exists business_banner_client_v433 on public.business_banners(client_id)where client_id is not null;
create function app_private.banner_businesses_v433()returns jsonb language plpgsql security definer set search_path=''as $$declare r jsonb;begin
 perform app_private.verified_phone();select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb)into r from(select b.id,b.name,p.city,p.district from public.businesses b join public.profiles p on p.phone=b.owner_phone where b.status='approved'and app_private.staff_can_v433('banners',p.city,array[p.district])order by b.name,b.id limit 100)x;return r;end$$;
create function public.banner_businesses_v433()returns jsonb language sql security invoker set search_path=''as $$select app_private.banner_businesses_v433()$$;
create function app_private.create_banner_v433(p_business uuid,p_title text,p_image text,p_client_id uuid)returns jsonb language plpgsql security definer set search_path=''as $$declare actor text:=app_private.verified_phone();v_city text;v_district text;item public.business_banners%rowtype;begin
 if p_client_id is null or length(trim(coalesce(p_title,'')))not between 1 and 160 or coalesce(p_image,'')!~'^https://'then raise exception 'შეავსე სათაური და სურათი';end if;
 select p.city,p.district into v_city,v_district from public.businesses b join public.profiles p on p.phone=b.owner_phone where b.id=p_business and b.status='approved';
 if not found or not app_private.staff_can_v433('banners',v_city,array[v_district])then raise exception 'Business outside assigned district'using errcode='42501';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_client_id::text,433));select *into item from public.business_banners where client_id=p_client_id;
 if found then if item.created_by<>actor then raise exception 'Request unavailable'using errcode='42501';end if;return jsonb_build_object('ok',true,'id',item.id);end if;
 insert into public.business_banners(business_id,title,image_url,created_by,active,client_id)values(p_business,trim(p_title),p_image,actor,true,p_client_id)returning *into item;
 insert into app_private.moderation_audit_v433(actor,kind,target,action)values(actor,'banners',item.id,'create');return jsonb_build_object('ok',true,'id',item.id);end$$;
create function public.create_banner_v433(p_business uuid,p_title text,p_image text,p_client_id uuid)returns jsonb language sql security invoker set search_path=''as $$select app_private.create_banner_v433(p_business,p_title,p_image,p_client_id)$$;
revoke all on function app_private.banner_businesses_v433(),public.banner_businesses_v433(),app_private.create_banner_v433(uuid,text,text,uuid),public.create_banner_v433(uuid,text,text,uuid)from public,anon;
grant execute on function app_private.banner_businesses_v433(),public.banner_businesses_v433(),app_private.create_banner_v433(uuid,text,text,uuid),public.create_banner_v433(uuid,text,text,uuid)to authenticated;
