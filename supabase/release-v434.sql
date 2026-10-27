-- v4.34 requires the already deployed v4.32 and v4.33 migrations.
begin;
-- Civic reports stay inside the app until staff records an actual official referral.
create table app_private.civic_reports_v434(
 id uuid primary key, owner_phone text not null references public.profiles(phone) on delete cascade,
 city text not null,district text not null,category text not null check(category in('road','lighting','water','waste','park','other')),
 description text not null check(length(description)between 10 and 3000),address text not null check(length(address)between 3 and 500),
 lat double precision,lng double precision,photo_path text not null,
 status text not null default 'received' check(status in('received','reviewing','referred','resolved','dismissed')),
 published boolean not null default false,agency text,external_ref text,note text,
 revision integer not null default 0,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 foreign key(city,district)references app_private.location_catalog(city,district),
 check((lat is null and lng is null)or(lat between -90 and 90 and lng between -180 and 180 and lat is not null and lng is not null))
);
create index civic_owner_v434 on app_private.civic_reports_v434(owner_phone,created_at desc,id desc);
create index civic_area_v434 on app_private.civic_reports_v434(city,district,created_at desc,id desc);
create table app_private.civic_history_v434(id bigint generated always as identity primary key,report_id uuid not null references app_private.civic_reports_v434(id) on delete cascade,actor text not null,status text not null,note text,agency text,external_ref text,created_at timestamptz not null default now());
create index civic_history_report_v434 on app_private.civic_history_v434(report_id,id);
alter table app_private.civic_reports_v434 enable row level security;
alter table app_private.civic_history_v434 enable row level security;
revoke all on app_private.civic_reports_v434,app_private.civic_history_v434 from public,anon,authenticated;
create function app_private.civic_visible_v434(p_id uuid)returns boolean language plpgsql stable security definer set search_path=''as $$declare actor text:=app_private.verified_phone();begin
 return exists(select 1 from app_private.civic_reports_v434 r where r.id=p_id and(r.owner_phone=actor or app_private.staff_can_v433('civic',r.city,array[r.district])or(r.published and exists(select 1 from public.profiles p where p.phone=actor and p.city=r.city and p.district=r.district))));end$$;
create function app_private.civic_file_read_v434(p_path text)returns boolean language plpgsql stable security definer set search_path=''as $$begin
 perform app_private.verified_phone();return exists(select 1 from app_private.civic_reports_v434 r where r.photo_path=p_path and app_private.civic_visible_v434(r.id));end$$;
revoke all on function app_private.civic_visible_v434(uuid)from public,anon,authenticated;
revoke all on function app_private.civic_file_read_v434(text)from public,anon;
grant execute on function app_private.civic_file_read_v434(text)to authenticated;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)values('civic-photos','civic-photos',false,5242880,array['image/jpeg','image/png','image/webp']);
-- Folder is an opaque authenticated account UUID; the reporter's phone is never in a shared image path.
create policy civic_upload_v434 on storage.objects for insert to authenticated with check(bucket_id='civic-photos'and split_part(name,'/',1)=auth.uid()::text and name~'^[0-9a-f-]{36}/[0-9a-f-]{36}\.(jpg|png|webp)$');
create policy civic_read_v434 on storage.objects for select to authenticated using(bucket_id='civic-photos'and app_private.civic_file_read_v434(name));
create function app_private.civic_create_v434(p_id uuid,p_data jsonb)returns jsonb language plpgsql security definer set search_path=''as $$
declare actor text:=app_private.verified_phone();r app_private.civic_reports_v434%rowtype;peer record;begin
 if p_id is null then raise exception 'Request ID required';end if;
 perform pg_advisory_xact_lock(hashtextextended(actor||':civic',0));
 select * into r from app_private.civic_reports_v434 where id=p_id;
 if found then if r.owner_phone<>actor then raise exception 'Request unavailable'using errcode='42501';end if;return jsonb_build_object('ok',true,'id',r.id);end if;
 if(select count(*)from app_private.civic_reports_v434 where owner_phone=actor and created_at>now()-interval '24 hours')>=5 then raise exception 'დღეში მაქსიმუმ 5 პრობლემის დამატება შეგიძლია';end if;
 if not exists(select 1 from public.profiles where phone=actor)then raise exception 'Profile required'using errcode='42501';end if;
 if auth.uid() is null or split_part(p_data->>'photo_path','/',1)is distinct from auth.uid()::text or split_part(p_data->>'photo_path','/',2)!~('^'||p_id::text||'\.(jpg|png|webp)$')or not exists(select 1 from storage.objects where bucket_id='civic-photos'and name=p_data->>'photo_path')then raise exception 'ფოტო ჯერ არ ატვირთულა'using errcode='42501';end if;
 insert into app_private.civic_reports_v434(id,owner_phone,city,district,category,description,address,lat,lng,photo_path)
 values(p_id,actor,p_data->>'city',p_data->>'district',p_data->>'category',trim(p_data->>'description'),trim(p_data->>'address'),(p_data->>'lat')::double precision,(p_data->>'lng')::double precision,p_data->>'photo_path')returning *into r;
 insert into app_private.civic_history_v434(report_id,actor,status,note)values(r.id,actor,'received','განაცხადი მიღებულია აპში.');
 -- Mandatory moderation notices do not silently disappear because of a social block.
 for peer in select p.phone from public.profiles p left join app_private.staff_scope_v433 s on s.phone=p.phone where(p.is_super_admin or p.admin_level='super'or(s.role='district'and s.city=r.city and s.district=r.district))and p.phone<>actor loop
 insert into public.notifications(recipient_phone,actor_phone,kind,title,body,source_event,is_read)values(peer.phone,actor,'civic_issue','უბნის ახალი პრობლემა',r.city||' • '||r.district||' — საჭიროა გადამოწმება','civic:'||r.id||':0',false)on conflict(recipient_phone,source_event)where source_event is not null do nothing;
 end loop;
 return jsonb_build_object('ok',true,'id',r.id);end$$;
create function app_private.civic_get_v434(p_id uuid)returns jsonb language plpgsql security definer set search_path=''as $$declare r app_private.civic_reports_v434%rowtype;result jsonb;can_manage boolean;begin
 if not app_private.civic_visible_v434(p_id)then raise exception 'განაცხადი მიუწვდომელია'using errcode='42501';end if;
 select *into r from app_private.civic_reports_v434 where id=p_id;
 can_manage:=app_private.staff_can_v433('civic',r.city,array[r.district]);
 result:=to_jsonb(r)-'owner_phone';
 -- Official tracking identifiers remain visible to the reporter and assigned staff only.
 if r.owner_phone<>app_private.verified_phone()and not can_manage then result:=result-'external_ref';end if;
 return result||jsonb_build_object('mine',r.owner_phone=app_private.verified_phone(),'can_manage',can_manage,'history',(select coalesce(jsonb_agg(jsonb_build_object('status',h.status,'note',h.note,'created_at',h.created_at)order by h.id),'[]'::jsonb)from app_private.civic_history_v434 h where h.report_id=r.id));end$$;
create function app_private.civic_list_v434(p_scope text default 'area',p_before timestamptz default null,p_before_id uuid default null)returns jsonb language plpgsql security definer set search_path=''as $$declare actor text:=app_private.verified_phone();r jsonb;begin
 if p_scope is null or p_scope not in('area','mine','manage')then raise exception 'Invalid scope';end if;
 if p_scope='manage'and app_private.staff_info_v433()->>'role'not in('super','district')then raise exception 'Forbidden'using errcode='42501';end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',x.id,'city',x.city,'district',x.district,'category',x.category,'description',left(x.description,180),'address',x.address,'status',x.status,'published',x.published,'created_at',x.created_at)order by x.created_at desc,x.id desc),'[]'::jsonb)into r
 from(select r.*from app_private.civic_reports_v434 r where
 (case p_scope when 'mine'then r.owner_phone=actor when 'manage'then app_private.staff_can_v433('civic',r.city,array[r.district])else r.published and exists(select 1 from public.profiles p where p.phone=actor and p.city=r.city and p.district=r.district)end)
 and(p_before is null or(r.created_at,r.id)<(p_before,p_before_id))order by r.created_at desc,r.id desc limit 30)x;
 return r;end$$;
create function app_private.civic_update_v434(p_id uuid,p_revision integer,p_status text,p_note text,p_published boolean default false,p_agency text default null,p_reference text default null)returns jsonb language plpgsql security definer set search_path=''as $$declare r app_private.civic_reports_v434%rowtype;actor text:=app_private.verified_phone();begin
 select *into r from app_private.civic_reports_v434 where id=p_id for update;
 if not found or not app_private.staff_can_v433('civic',r.city,array[r.district])then raise exception 'Forbidden'using errcode='42501';end if;
 if p_revision is distinct from r.revision then return jsonb_build_object('ok',false,'message','განაცხადი შეიცვალა. გახსენი თავიდან.');end if;
 if p_status is null or p_status not in('reviewing','referred','resolved','dismissed')or p_published is null then raise exception 'Invalid status';end if;
 if length(trim(coalesce(p_note,'')))not between 3 and 1000 then raise exception 'მიუთითე სტატუსის ცვლილების განმარტება';end if;
 if p_status='referred'and(length(trim(coalesce(p_agency,'')))not between 3 and 200 or length(trim(coalesce(p_reference,'')))not between 2 and 160)then raise exception 'მიუთითე სამსახური და ოფიციალური მიმართვის ნომერი';end if;
 if r.status in('resolved','dismissed')and p_status<>'reviewing'and p_status<>r.status then raise exception 'ჯერ ხელახლა გახსენი განხილვისთვის';end if;
 if r.status='received'and p_status='resolved'then raise exception 'ჯერ გადაამოწმე განაცხადი';end if;
 update app_private.civic_reports_v434 set status=p_status,note=trim(p_note),published=p_published and p_status<>'dismissed',agency=case when p_status='referred'then trim(p_agency)else r.agency end,external_ref=case when p_status='referred'then trim(p_reference)else r.external_ref end,revision=revision+1,updated_at=now()where id=p_id returning *into r;
 insert into app_private.civic_history_v434(report_id,actor,status,note,agency,external_ref)values(r.id,actor,r.status,r.note,r.agency,r.external_ref);
 insert into app_private.moderation_audit_v433(actor,kind,target,action)values(actor,'civic',r.id,p_status);
 if r.owner_phone<>actor then insert into public.notifications(recipient_phone,actor_phone,kind,title,body,source_event,is_read)values(r.owner_phone,actor,'civic_issue','შენი უბნის პრობლემის სტატუსი განახლდა',left(r.note,140),'civic:'||r.id||':'||r.revision,false)on conflict(recipient_phone,source_event)where source_event is not null do nothing;end if;
 return jsonb_build_object('ok',true,'id',r.id);end$$;
create function public.civic_create_v434(p_id uuid,p_data jsonb)returns jsonb language sql security invoker set search_path=''as $$select app_private.civic_create_v434(p_id,p_data)$$;
create function public.civic_get_v434(p_id uuid)returns jsonb language sql security invoker set search_path=''as $$select app_private.civic_get_v434(p_id)$$;
create function public.civic_list_v434(p_scope text default 'area',p_before timestamptz default null,p_before_id uuid default null)returns jsonb language sql security invoker set search_path=''as $$select app_private.civic_list_v434(p_scope,p_before,p_before_id)$$;
create function public.civic_update_v434(p_id uuid,p_revision integer,p_status text,p_note text,p_published boolean default false,p_agency text default null,p_reference text default null)returns jsonb language sql security invoker set search_path=''as $$select app_private.civic_update_v434(p_id,p_revision,p_status,p_note,p_published,p_agency,p_reference)$$;
revoke all on function public.civic_create_v434(uuid,jsonb),app_private.civic_create_v434(uuid,jsonb),public.civic_get_v434(uuid),app_private.civic_get_v434(uuid),public.civic_list_v434(text,timestamptz,uuid),app_private.civic_list_v434(text,timestamptz,uuid),public.civic_update_v434(uuid,integer,text,text,boolean,text,text),app_private.civic_update_v434(uuid,integer,text,text,boolean,text,text)from public,anon;
grant execute on function public.civic_create_v434(uuid,jsonb),app_private.civic_create_v434(uuid,jsonb),public.civic_get_v434(uuid),app_private.civic_get_v434(uuid),public.civic_list_v434(text,timestamptz,uuid),app_private.civic_list_v434(text,timestamptz,uuid),public.civic_update_v434(uuid,integer,text,text,boolean,text,text),app_private.civic_update_v434(uuid,integer,text,text,boolean,text,text)to authenticated;

create function app_private.notification_category_v434(p_kind text)returns text language sql immutable set search_path=''as $$select case when p_kind in('direct_message','group_message')then 'messages'when p_kind in('daily_photo','daily_reminder')then 'photos'when p_kind in('service_order','service_order_update','approval_request')then 'services'when p_kind in('hot_news','civic_issue')then 'neighborhood'when p_kind in('post_like','comment','reply','comment_like','friend_request','friend_accepted')then 'social'else 'other'end$$;
revoke all on function app_private.notification_category_v434(text)from public,anon,authenticated;
create index notifications_page_v434 on public.notifications(recipient_phone,created_at desc,id desc);
create function app_private.notifications_page_v434(p_category text default 'all',p_unread boolean default false,p_before timestamptz default null,p_before_id uuid default null)returns jsonb language plpgsql security definer set search_path=''as $$declare actor text:=app_private.verified_phone();r jsonb;begin
 if p_category is null or p_category not in('all','messages','photos','services','neighborhood','social','other')then raise exception 'Invalid category';end if;
 select coalesce(jsonb_agg(to_jsonb(x)order by x.created_at desc,x.id desc),'[]'::jsonb)into r from(select n.id,n.kind,n.title,n.body,n.created_at,coalesce(n.is_read,false)is_read,app_private.notification_category_v434(n.kind)category from public.notifications n where n.recipient_phone=actor and(p_category='all'or app_private.notification_category_v434(n.kind)=p_category)and(not p_unread or not coalesce(n.is_read,false))and(p_before is null or(n.created_at,n.id)<(p_before,p_before_id))order by n.created_at desc,n.id desc limit 30)x;
 return jsonb_build_object('items',r,'through',now());end$$;
create function app_private.notifications_read_all_v434(p_through timestamptz)returns jsonb language plpgsql security definer set search_path=''as $$declare actor text:=app_private.verified_phone();n integer;begin
 if p_through is null or p_through>now()+interval '5 seconds'then raise exception 'Invalid timestamp';end if;
 update public.notifications set is_read=true where recipient_phone=actor and not coalesce(is_read,false)and created_at<=least(p_through,now());get diagnostics n=row_count;return jsonb_build_object('ok',true,'count',n);end$$;
create function public.notifications_page_v434(p_category text default 'all',p_unread boolean default false,p_before timestamptz default null,p_before_id uuid default null)returns jsonb language sql security invoker set search_path=''as $$select app_private.notifications_page_v434(p_category,p_unread,p_before,p_before_id)$$;
create function public.notifications_read_all_v434(p_through timestamptz)returns jsonb language sql security invoker set search_path=''as $$select app_private.notifications_read_all_v434(p_through)$$;
revoke all on function public.notifications_page_v434(text,boolean,timestamptz,uuid),app_private.notifications_page_v434(text,boolean,timestamptz,uuid),public.notifications_read_all_v434(timestamptz),app_private.notifications_read_all_v434(timestamptz)from public,anon;
grant execute on function public.notifications_page_v434(text,boolean,timestamptz,uuid),app_private.notifications_page_v434(text,boolean,timestamptz,uuid),public.notifications_read_all_v434(timestamptz),app_private.notifications_read_all_v434(timestamptz)to authenticated;
create or replace function app_private.resolve_notification(p_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare me text:=app_private.verified_phone(); n public.notifications%rowtype; target uuid; result jsonb; prefix text;
begin
 select * into n from public.notifications where id=p_id and recipient_phone=me;
 if not found then raise exception 'Notification unavailable' using errcode='42501'; end if;
 prefix:=split_part(n.source_event,':',1);
 if split_part(coalesce(n.source_event,''),':',2)~*'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'then target:=split_part(n.source_event,':',2)::uuid;end if;
 if prefix='civic'then
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
