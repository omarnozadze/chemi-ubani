-- Durable account erasure. Storage API and Auth Admin API are completed by deletion-worker.
create table app_private.account_deletions_v436(id uuid primary key default gen_random_uuid(),user_id uuid unique,phone text,status text not null default 'pending'check(status in('pending','completed')),created_at timestamptz not null default now(),completed_at timestamptz);
alter table app_private.account_deletions_v436 enable row level security;
revoke all on app_private.account_deletions_v436 from public,anon,authenticated;
create function app_private.account_delete_preview_v436()returns jsonb language plpgsql security definer set search_path=''as $$
declare actor text:=app_private.verified_phone();begin
 return jsonb_build_object('active_orders',(select count(*)from public.service_orders where actor in(customer_phone,provider_phone)and(status not in('done','cancelled','refunded')or funds_held)),'shared_groups',(select count(*)from public.live_chats c where c.owner_phone=actor and exists(select 1 from public.live_chat_members m where m.chat_id=c.id and m.phone<>actor)),'last_super',exists(select 1 from public.profiles where phone=actor and(is_super_admin or admin_level='super'))and not exists(select 1 from public.profiles where phone<>actor and(is_super_admin or admin_level='super')));end$$;
create function app_private.request_account_delete_v436(p_confirmation text)returns jsonb language plpgsql security definer set search_path=''as $$
<<request_account_delete_v436>>
declare actor text:=app_private.verified_phone();uid uuid:=auth.uid();preview jsonb;jid uuid;begin
 if p_confirmation is distinct from 'DELETE_MY_ACCOUNT'then raise exception 'Confirmation required';end if;
 if not exists(select 1 from jsonb_array_elements(coalesce(auth.jwt()->'amr','[]'))a where a->>'method'='otp'and(a->>'timestamp')~'^[0-9]{10}$'and(a->>'timestamp')::bigint between extract(epoch from now()-interval '5 minutes')and extract(epoch from now()+interval '30 seconds'))then raise exception 'ხელახლა დაადასტურე ნომერი SMS-კოდით.'using errcode='42501';end if;
 perform pg_advisory_xact_lock(hashtextextended('account-erasure-v436',0));
 perform 1 from public.profiles where phone=actor for update;
 if not found then raise exception 'Profile unavailable'using errcode='42501';end if;
 preview:=app_private.account_delete_preview_v436();
 if(preview->>'active_orders')::int>0 then raise exception 'ჯერ დაასრულე მიმდინარე შეკვეთები და გადახდის საკითხები.';end if;
 if(preview->>'shared_groups')::int>0 then raise exception 'ჯერ წაშალე შენი ჯგუფები ან გადააბარე მფლობელობა.';end if;
 if(preview->>'last_super')::boolean then raise exception 'ჯერ დანიშნე სხვა სუპერ ადმინისტრატორი.';end if;
 insert into app_private.account_deletions_v436(user_id,phone)values(uid,actor)returning id into jid;
 insert into app_private.file_deletions_v436(bucket,path,object_id)select bucket_id,name,id from storage.objects where owner_id=uid::text or split_part(name,'/',1)in(uid::text,actor)on conflict(bucket,path)do nothing;
 -- Explicit non-FK records; FK children are removed by the profile's ON DELETE CASCADE constraints.
 delete from public.service_orders where actor in(customer_phone,provider_phone);
 delete from public.hot_news where author_phone=actor;
 delete from public.admin_campaigns where author_phone=actor;
 delete from public.notifications where actor_phone=actor;
 delete from public.app_errors where phone=actor;
 delete from public.campaign_events where phone=actor;
 delete from public.admin_audit where actor_phone=actor;
 delete from public.push_delivery_log where recipient_phone=actor;
 delete from app_private.message_requests where phone=actor;
 delete from app_private.write_limits where phone=actor;
 delete from app_private.staff_scope_v433 where phone=actor;
 delete from app_private.location_permits_v435 where phone=actor;
 delete from app_private.places_quota_v432 t where t.actor=request_account_delete_v436.actor;
 -- Operational audit entries are removed for this identity, not published under the old number.
 delete from app_private.moderation_audit_v433 t where t.actor=request_account_delete_v436.actor;
 delete from app_private.civic_history_v434 t where t.actor=request_account_delete_v436.actor;
 update app_private.location_requests_v435 set reviewed_by=null where reviewed_by=actor;
 update public.specialist_announcements set reviewed_by=null where reviewed_by=actor;
 delete from public.profiles where phone=actor;
 return jsonb_build_object('ok',true,'id',jid,'status','pending');end$$;
create function public.account_delete_preview_v436()returns jsonb language sql security invoker set search_path=''as $$select app_private.account_delete_preview_v436()$$;
revoke all on function public.account_delete_preview_v436(),app_private.account_delete_preview_v436()from public,anon;
grant execute on function public.account_delete_preview_v436(),app_private.account_delete_preview_v436()to authenticated;
create function public.request_account_delete_v436(p_confirmation text)returns jsonb language sql security invoker set search_path=''as $$select app_private.request_account_delete_v436(p_confirmation)$$;
revoke all on function public.request_account_delete_v436(text),app_private.request_account_delete_v436(text)from public,anon;
grant execute on function public.request_account_delete_v436(text),app_private.request_account_delete_v436(text)to authenticated;
-- Existing JWTs are unusable immediately after the request, before Auth cleanup finishes.
alter function app_private.verified_phone()rename to verified_phone_before436;
revoke all on function app_private.verified_phone_before436()from public,anon,authenticated;
create function app_private.verified_phone()returns text language plpgsql security definer set search_path=''as $$begin
 if exists(select 1 from app_private.account_deletions_v436 where user_id=auth.uid()and status='pending')then raise exception 'Account deletion in progress'using errcode='42501';end if;
 return app_private.verified_phone_before436();end$$;
revoke all on function app_private.verified_phone()from public,anon,authenticated;
-- Restrictive policy also blocks uploading while the deletion worker drains files.
create function app_private.account_upload_allowed_v436()returns boolean language sql stable security definer set search_path=''as $$select auth.uid()is not null and not exists(select 1 from app_private.account_deletions_v436 where user_id=auth.uid()and status='pending')$$;
revoke all on function app_private.account_upload_allowed_v436()from public,anon;
grant execute on function app_private.account_upload_allowed_v436()to authenticated;
create policy account_upload_v436 on storage.objects as restrictive for insert to authenticated with check(app_private.account_upload_allowed_v436());
create policy account_update_v436 on storage.objects as restrictive for update to authenticated using(app_private.account_upload_allowed_v436())with check(app_private.account_upload_allowed_v436());
create function public.deletion_status_v436()returns jsonb language sql security definer set search_path=''as $$select coalesce((select jsonb_build_object('id',id,'status',status)from app_private.account_deletions_v436 where user_id=auth.uid()),'{}')$$;
revoke all on function public.deletion_status_v436()from public,anon;grant execute on function public.deletion_status_v436()to authenticated;
-- Service-role-only worker APIs; no client may enumerate paths, finish jobs or erase Auth users.
create function public.deletion_work_v436()returns jsonb language plpgsql security definer set search_path=''as $$begin
 -- Re-scan pending account owners: an upload already in flight can finish after request commit.
 insert into app_private.file_deletions_v436(bucket,path,object_id)select o.bucket_id,o.name,o.id from storage.objects o join app_private.account_deletions_v436 j on j.status='pending'and(o.owner_id=j.user_id::text or split_part(o.name,'/',1)in(j.user_id::text,j.phone))on conflict(bucket,path)do nothing;
 return jsonb_build_object('files',(select coalesce(jsonb_agg(to_jsonb(q)),'[]')from(select d.* from app_private.file_deletions_v436 d order by attempts,id limit 100)q),'accounts',(select coalesce(jsonb_agg(to_jsonb(q)),'[]')from(select id,user_id from app_private.account_deletions_v436 j where status='pending'and not exists(select 1 from storage.objects o where o.owner_id=j.user_id::text or split_part(o.name,'/',1)in(j.user_id::text,j.phone))order by created_at limit 10)q));end$$;
create function public.deletion_file_done_v436(p_id bigint,p_ok boolean)returns void language plpgsql security definer set search_path=''as $$begin if p_ok then delete from app_private.file_deletions_v436 where id=p_id;else update app_private.file_deletions_v436 set attempts=attempts+1 where id=p_id;end if;end$$;
create function public.deletion_account_done_v436(p_id uuid)returns void language sql security definer set search_path=''as $$update app_private.account_deletions_v436 set status='completed',completed_at=now(),phone=null,user_id=null where id=p_id and status='pending'$$;
revoke all on function public.deletion_work_v436(),public.deletion_file_done_v436(bigint,boolean),public.deletion_account_done_v436(uuid)from public,anon,authenticated;
grant execute on function public.deletion_work_v436(),public.deletion_file_done_v436(bigint,boolean),public.deletion_account_done_v436(uuid)to service_role;
notify pgrst,'reload schema';
create function public.deletion_file_action_v436(p_id bigint)returns text language plpgsql security definer set search_path=''as $$
declare job app_private.file_deletions_v436%rowtype;t text;used boolean;begin
 select *into job from app_private.file_deletions_v436 where id=p_id;
 if not found or not exists(select 1 from storage.objects where bucket_id=job.bucket and name=job.path and id=job.object_id)then return 'skip';end if;
 if exists(select 1 from app_private.account_deletions_v436 j join storage.objects o on o.bucket_id=job.bucket and o.name=job.path where j.status='pending'and(o.owner_id=j.user_id::text or split_part(o.name,'/',1)in(j.phone,j.user_id::text)))then return 'delete';end if;
 foreach t in array array['posts','daily_moments','my_day_posts','specialist_announcements','marketplace_listings','live_chats','live_chat_messages','direct_chat_messages','profiles','businesses','business_banners','admin_campaigns']loop
 execute format('select exists(select 1 from public.%I r where exists(select 1 from jsonb_each_text(to_jsonb(r))f where f.key in(''image_url'',''photo_url'',''back_image_url'',''front_image_url'',''avatar_url'')and position($1 in f.value)>0)or(to_jsonb(r)->''attachment''->>''path''=$2 and $3=''chat-files''))',t)into used using '/'||job.bucket||'/'||job.path,job.path,job.bucket;
 if used then return 'skip';end if;
 end loop;return 'delete';end$$;
revoke all on function public.deletion_file_action_v436(bigint)from public,anon,authenticated;grant execute on function public.deletion_file_action_v436(bigint)to service_role;
