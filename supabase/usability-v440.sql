alter table public.notification_preferences add column advertising boolean not null default true;
create or replace function app_private.get_notification_preferences()returns jsonb language plpgsql security definer set search_path='' as $$
declare actor text:=app_private.verified_phone();r jsonb;begin
 select to_jsonb(p)-'phone' into r from public.notification_preferences p where phone=actor;
 return coalesce(r,'{"enabled":true,"advertising":true,"messages":true,"daily_photo":true,"reactions":true,"friends":true,"hot_news":true,"services":true,"other":true,"quiet_enabled":false,"quiet_start":1380,"quiet_end":480}'::jsonb);end $$;
create or replace function app_private.set_notification_preferences(p_settings jsonb)returns jsonb language plpgsql security definer set search_path='' as $$
declare actor text:=app_private.verified_phone();r public.notification_preferences%rowtype;begin
 select * into r from jsonb_populate_record(null::public.notification_preferences,p_settings);
 if r.quiet_enabled and r.quiet_start=r.quiet_end then raise exception 'Quiet hours need different start and end';end if;
 insert into public.notification_preferences(phone,enabled,messages,daily_photo,reactions,friends,hot_news,advertising,services,other,quiet_enabled,quiet_start,quiet_end)
 values(actor,r.enabled,r.messages,r.daily_photo,r.reactions,r.friends,r.hot_news,coalesce(r.advertising,true),r.services,r.other,r.quiet_enabled,r.quiet_start,r.quiet_end)
 on conflict(phone)do update set enabled=excluded.enabled,messages=excluded.messages,daily_photo=excluded.daily_photo,reactions=excluded.reactions,friends=excluded.friends,hot_news=excluded.hot_news,advertising=excluded.advertising,services=excluded.services,other=excluded.other,quiet_enabled=excluded.quiet_enabled,quiet_start=excluded.quiet_start,quiet_end=excluded.quiet_end,updated_at=now();return app_private.get_notification_preferences();end $$;
alter table app_private.civic_reports_v434 add column neighborhood text;
create index civic_neighborhood_v440 on app_private.civic_reports_v434(city,district,neighborhood,created_at desc,id desc)where published;
create or replace function app_private.assert_arrival_v432(a timestamptz,b timestamptz)returns void language plpgsql set search_path=''as $$begin
 if a is null or b is null or not isfinite(a)or not isfinite(b)or a<=now()or b<a then raise exception 'მიუთითე მომავალი მოსვლის დრო.';end if;end$$;
create or replace function app_private.civic_visible_v434(p_id uuid)returns boolean language plpgsql stable security definer set search_path=''as $$declare actor text:=app_private.verified_phone();begin
 return exists(select 1 from app_private.civic_reports_v434 r where r.id=p_id and(r.owner_phone=actor or app_private.staff_can_v433('civic',r.city,array[r.district])or(r.published and exists(select 1 from public.profiles p where p.phone=actor and p.city=r.city and p.district=r.district and nullif(r.neighborhood,'')is not null and p.neighborhood=r.neighborhood))));end$$;
create or replace function app_private.civic_list_v434(p_scope text default 'area',p_before timestamptz default null,p_before_id uuid default null)returns jsonb language plpgsql security definer set search_path=''as $$declare actor text:=app_private.verified_phone();r jsonb;begin
 if p_scope is null or p_scope not in('area','mine','manage')then raise exception 'Invalid scope';end if;
 if p_scope='manage'and app_private.staff_info_v433()->>'role'not in('super','district')then raise exception 'Forbidden'using errcode='42501';end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',x.id,'city',x.city,'district',x.district,'neighborhood',x.neighborhood,'category',x.category,'description',left(x.description,180),'address',x.address,'status',x.status,'published',x.published,'created_at',x.created_at)order by x.created_at desc,x.id desc),'[]'::jsonb)into r
 from(select r.*from app_private.civic_reports_v434 r where
 (case p_scope when 'mine'then r.owner_phone=actor when 'manage'then app_private.staff_can_v433('civic',r.city,array[r.district])else r.published and exists(select 1 from public.profiles p where p.phone=actor and p.city=r.city and p.district=r.district and nullif(r.neighborhood,'')is not null and p.neighborhood=r.neighborhood)end)
 and(p_before is null or(r.created_at,r.id)<(p_before,p_before_id))order by r.created_at desc,r.id desc limit 30)x;
 return r;end$$;
create or replace function app_private.civic_create_v434(p_id uuid,p_data jsonb)returns jsonb language plpgsql security definer set search_path=''as $$
declare actor text:=app_private.verified_phone();r app_private.civic_reports_v434%rowtype;peer record;begin
 if p_id is null then raise exception 'Request ID required';end if;
 perform pg_advisory_xact_lock(hashtextextended(actor||':civic',0));
 select * into r from app_private.civic_reports_v434 where id=p_id;
 if found then if r.owner_phone<>actor then raise exception 'Request unavailable'using errcode='42501';end if;return jsonb_build_object('ok',true,'id',r.id);end if;
 if(select count(*)from app_private.civic_reports_v434 where owner_phone=actor and created_at>now()-interval '24 hours')>=5 then raise exception 'დღეში მაქსიმუმ 5 პრობლემის დამატება შეგიძლია';end if;
 if not exists(select 1 from public.profiles where phone=actor)then raise exception 'Profile required'using errcode='42501';end if;
 if auth.uid() is null or split_part(p_data->>'photo_path','/',1)is distinct from auth.uid()::text or split_part(p_data->>'photo_path','/',2)!~('^'||p_id::text||'\.(jpg|png|webp)$')or not exists(select 1 from storage.objects where bucket_id='civic-photos'and name=p_data->>'photo_path')then raise exception 'ფოტო ჯერ არ ატვირთულა'using errcode='42501';end if;
 if not exists(select 1 from app_private.location_catalog where city=p_data->>'city'and district=p_data->>'district'and nullif(p_data->>'neighborhood','')is not null and neighborhoods?(p_data->>'neighborhood'))then raise exception 'აირჩიე კონკრეტული უბანი.';end if;
 insert into app_private.civic_reports_v434(id,owner_phone,city,district,neighborhood,category,description,address,lat,lng,photo_path)
 values(p_id,actor,p_data->>'city',p_data->>'district',p_data->>'neighborhood',p_data->>'category',trim(p_data->>'description'),trim(p_data->>'address'),(p_data->>'lat')::double precision,(p_data->>'lng')::double precision,p_data->>'photo_path')returning *into r;
 insert into app_private.civic_history_v434(report_id,actor,status,note)values(r.id,actor,'received','განაცხადი მიღებულია აპში.');
 -- Mandatory moderation notices do not silently disappear because of a social block.
 for peer in select p.phone from public.profiles p left join app_private.staff_scope_v433 s on s.phone=p.phone where(p.is_super_admin or p.admin_level='super'or(s.role='district'and s.city=r.city and s.district=r.district))and p.phone<>actor loop
 insert into public.notifications(recipient_phone,actor_phone,kind,title,body,source_event,is_read)values(peer.phone,actor,'civic_issue','უბნის ახალი პრობლემა',r.city||' • '||r.district||' — საჭიროა გადამოწმება','civic:'||r.id||':0',false)on conflict(recipient_phone,source_event)where source_event is not null do nothing;
 end loop;
 return jsonb_build_object('ok',true,'id',r.id);end$$;
create or replace function app_private.civic_update_v434(p_id uuid,p_revision integer,p_status text,p_note text,p_published boolean default false,p_agency text default null,p_reference text default null)returns jsonb language plpgsql security definer set search_path=''as $$declare r app_private.civic_reports_v434%rowtype;actor text:=app_private.verified_phone();begin
 select *into r from app_private.civic_reports_v434 where id=p_id for update;
 if not found or not app_private.staff_can_v433('civic',r.city,array[r.district])then raise exception 'Forbidden'using errcode='42501';end if;
 if p_published and nullif(r.neighborhood,'')is null then raise exception 'გამოქვეყნებამდე მიუთითე პრობლემის კონკრეტული უბანი.';end if;
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

create function app_private.civic_neighborhood_v440(p_id uuid,p_neighborhood text)returns jsonb language plpgsql security definer set search_path=''as $$declare r app_private.civic_reports_v434%rowtype;begin
 select *into r from app_private.civic_reports_v434 where id=p_id for update;
 if not found or not app_private.staff_can_v433('civic',r.city,array[r.district])then raise exception 'Forbidden'using errcode='42501';end if;
 if not exists(select 1 from app_private.location_catalog where city=r.city and district=r.district and nullif(p_neighborhood,'')is not null and neighborhoods?p_neighborhood)then raise exception 'აირჩიე კონკრეტული უბანი.';end if;
 update app_private.civic_reports_v434 set neighborhood=p_neighborhood,published=false,revision=revision+1,updated_at=now()where id=p_id;
 insert into app_private.moderation_audit_v433(actor,kind,target,action)values(app_private.verified_phone(),'civic',p_id,'set_neighborhood');return jsonb_build_object('ok',true);end$$;
create function public.civic_neighborhood_v440(p_id uuid,p_neighborhood text)returns jsonb language sql security invoker set search_path=''as $$select app_private.civic_neighborhood_v440(p_id,p_neighborhood)$$;
revoke all on function app_private.civic_neighborhood_v440(uuid,text),public.civic_neighborhood_v440(uuid,text)from public,anon;
grant execute on function app_private.civic_neighborhood_v440(uuid,text),public.civic_neighborhood_v440(uuid,text)to authenticated;
notify pgrst,'reload schema';
-- Read receipts use existing read watermarks, never delivery guesses.
create or replace function app_private.conversation_page(p_kind text,p_id uuid,p_before timestamptz default null,p_before_id uuid default null)returns jsonb language plpgsql security definer set search_path=''as $$declare rows jsonb;r jsonb;watermark timestamptz;actor text:=app_private.verified_phone();begin
 rows:=app_private.chat_page_data(p_kind,p_id,null,p_before,p_before_id,null,50);
 if p_kind='direct'then select d.last_read_at into watermark from public.direct_chat_reads d join public.direct_chat_threads t on t.id=d.thread_id where t.id=p_id and d.phone=case when t.user_a=actor then t.user_b else t.user_a end;
 select coalesce(jsonb_agg(value||jsonb_build_object('peer_read',value->>'sender_phone'=actor and watermark>=(value->>'created_at')::timestamptz)order by ord),'[]')into r from jsonb_array_elements(rows)with ordinality e(value,ord);return r;end if;return rows;end$$;
create table app_private.group_mutes_v440(phone text not null references public.profiles(phone)on delete cascade,chat_id uuid not null references public.live_chats(id)on delete cascade,primary key(phone,chat_id));
alter table app_private.group_mutes_v440 enable row level security;revoke all on app_private.group_mutes_v440 from public,anon,authenticated;
create function app_private.group_mute_v440(p_id uuid,p_muted boolean default null)returns jsonb language plpgsql security definer set search_path=''as $$declare actor text:=app_private.verified_phone();begin
 perform app_private.assert_conversation('group',p_id);
 if p_muted is true then insert into app_private.group_mutes_v440 values(actor,p_id)on conflict do nothing;
 elsif p_muted is false then delete from app_private.group_mutes_v440 where phone=actor and chat_id=p_id;end if;
 return jsonb_build_object('muted',exists(select 1 from app_private.group_mutes_v440 where phone=actor and chat_id=p_id));end$$;
create function public.group_mute_v440(p_id uuid,p_muted boolean default null)returns jsonb language sql security invoker set search_path=''as $$select app_private.group_mute_v440(p_id,p_muted)$$;
revoke all on function app_private.group_mute_v440(uuid,boolean),public.group_mute_v440(uuid,boolean)from public,anon;
grant execute on function app_private.group_mute_v440(uuid,boolean),public.group_mute_v440(uuid,boolean)to authenticated;
create or replace function public.push_delivery_allowed(p_notification_id uuid)returns boolean language sql security definer set search_path=''as $$
 select coalesce((select app_private.notification_allowed(to_jsonb(p),n.kind,now())and
 case when n.source_event like 'daily-reminder:%'then
 n.source_event='daily-reminder:'||to_char(now()at time zone 'Asia/Tbilisi','YYYY-MM-DD:HH24')
 and exists(select 1 from app_private.daily_reminder_preferences r where r.phone=n.recipient_phone and r.enabled)
 and app_private.daily_photo_missing(n.recipient_phone,now())else true end
 and(coalesce(p.advertising,true)or not exists(select 1 from public.hot_news h where n.source_event='hot:'||h.id and h.category='რეკლამა'))
 and not exists(select 1 from public.live_chat_messages m join app_private.group_mutes_v440 g on g.chat_id=m.chat_id and g.phone=n.recipient_phone where n.source_event='group:'||m.id)
 from public.notifications n left join public.notification_preferences p on p.phone=n.recipient_phone where n.id=p_notification_id),false)$$;
notify pgrst,'reload schema';

create function app_private.report_content_v440(p_kind text,p_id uuid,p_category text,p_details text default '')returns jsonb language plpgsql security definer set search_path=''as $$declare actor text:=app_private.verified_phone();target text;begin
 if p_kind='post'then if app_private.post_target(p_id)is null then raise exception 'Content unavailable'using errcode='42501';end if;select author_phone into target from public.posts where id=p_id;
 elsif p_kind='service'then if not exists(select 1 from jsonb_array_elements(app_private.specialist_ads_v432('public'))x where x->>'id'=p_id::text)then raise exception 'Content unavailable'using errcode='42501';end if;select owner_phone into target from public.specialist_announcements where id=p_id;
 elsif p_kind='market'then select owner_phone into target from app_private.legacy_list_marketplace(actor)where id=p_id;
 else raise exception 'Invalid content type';end if;
 if target is null or target=actor then raise exception 'Content unavailable'using errcode='42501';end if;
 if p_category not in('spam','harassment','fraud','inappropriate','other')or p_category is null or length(coalesce(p_details,''))>1500 then raise exception 'Invalid report';end if;
 return public.report_user(actor,target,p_category,'['||p_kind||':'||p_id||'] '||coalesce(p_details,''));end$$;
create function public.report_content_v440(p_kind text,p_id uuid,p_category text,p_details text default '')returns jsonb language sql security invoker set search_path=''as $$select app_private.report_content_v440(p_kind,p_id,p_category,p_details)$$;
revoke all on function app_private.report_content_v440(text,uuid,text,text),public.report_content_v440(text,uuid,text,text)from public,anon;
grant execute on function app_private.report_content_v440(text,uuid,text,text),public.report_content_v440(text,uuid,text,text)to authenticated;
notify pgrst,'reload schema';
