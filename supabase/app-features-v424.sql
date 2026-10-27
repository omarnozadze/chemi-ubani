-- Requires verified-api-v424.sql and notification-events.sql.
begin;
create table if not exists app_private.message_requests(
 phone text not null, client_id uuid not null, payload jsonb not null, result jsonb not null,
 created_at timestamptz not null default now(), primary key(phone,client_id)
);
revoke all on app_private.message_requests from public,anon,authenticated;
create or replace function app_private.send_chat_message_verified(p_kind text,p_id uuid,p_body text,p_image_url text,p_client_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare me text:=app_private.verified_phone(); request jsonb:=jsonb_build_object('kind',p_kind,'id',p_id,'body',p_body,'image',p_image_url); saved app_private.message_requests%rowtype; response jsonb;
begin
 if p_client_id is null or length(coalesce(p_body,''))>5000 then raise exception 'Invalid message'; end if;
 perform pg_advisory_xact_lock(hashtextextended(me||p_client_id::text,0));
 select * into saved from app_private.message_requests where phone=me and client_id=p_client_id;
 if found then
  if saved.payload<>request then raise exception 'Request already used'; end if;
  return saved.result;
 end if;
 if p_kind='direct' then response:=public.send_direct_message(me,p_id,p_body,p_image_url);
 elsif p_kind='group' then response:=public.send_live_chat_message(me,p_id,p_body,p_image_url);
 else raise exception 'Invalid conversation'; end if;
 if response->>'ok'='true' then insert into app_private.message_requests(phone,client_id,payload,result) values(me,p_client_id,request,response); end if;
 return response;
end $$;
create or replace function app_private.mark_conversation_read_v423(p_phone text,p_kind text,p_id uuid,p_through timestamptz)
returns jsonb language plpgsql security definer set search_path='' as $$
declare me text:=app_private.verified_phone(); cutoff timestamptz;
begin
 perform app_private.assert_actor(p_phone);
 if p_kind='direct' then
  if not exists(select 1 from public.direct_chat_threads where id=p_id and me in(user_a,user_b)) then raise exception 'Not a member' using errcode='42501'; end if;
  select max(created_at) into cutoff from public.direct_chat_messages where thread_id=p_id and created_at<=least(p_through,now());
  if cutoff is not null then insert into public.direct_chat_reads(thread_id,phone,last_read_at) values(p_id,me,cutoff) on conflict(thread_id,phone) do update set last_read_at=greatest(public.direct_chat_reads.last_read_at,excluded.last_read_at); end if;
 elsif p_kind='group' then
  if not exists(select 1 from public.live_chat_members where chat_id=p_id and phone=me) then raise exception 'Not a member' using errcode='42501'; end if;
  select max(created_at) into cutoff from public.live_chat_messages where chat_id=p_id and created_at<=least(p_through,now());
  if cutoff is not null then update public.live_chat_members set last_read_at=greatest(last_read_at,cutoff) where chat_id=p_id and phone=me; end if;
 else raise exception 'Invalid conversation'; end if;
 return jsonb_build_object('ok',true);
end $$;
create or replace function app_private.resolve_notification(p_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare me text:=app_private.verified_phone(); n public.notifications%rowtype; target uuid; result jsonb; prefix text;
begin
 select * into n from public.notifications where id=p_id and recipient_phone=me;
 if not found then raise exception 'Notification unavailable' using errcode='42501'; end if;
 prefix:=split_part(n.source_event,':',1);
 if coalesce(n.source_event,'')<>'' then target:=split_part(n.source_event,':',2)::uuid; end if;
 if prefix='direct' then
  select jsonb_build_object('screen','chat','kind','direct','id',t.id,'other',jsonb_build_object('phone',p.phone,'name',p.full_name,'avatarUrl',p.avatar_url,'district',p.district)) into result
  from public.direct_chat_messages m join public.direct_chat_threads t on t.id=m.thread_id join public.profiles p on p.phone=case when t.user_a=me then t.user_b else t.user_a end
  where m.id=target and me in(t.user_a,t.user_b) and not public.is_user_blocked(me,p.phone);
 elsif prefix='group' then
  select jsonb_build_object('screen','chat','kind','group','id',c.id,'name',c.name) into result from public.live_chat_messages m join public.live_chats c on c.id=m.chat_id
  where m.id=target and exists(select 1 from public.live_chat_members where chat_id=c.id and phone=me);
 elsif prefix='order' then
  select jsonb_build_object('screen',case when provider_phone=me then 'specialistCabinet' else 'myOrders' end,'id',id) into result from public.service_orders where id=target and me in(customer_phone,provider_phone);
 elsif prefix='daily' then
  select jsonb_build_object('screen','dailyMoment','id',d.id) into result from public.list_daily_moments(me) d where d.id=target;
 elsif prefix='myday' then result:=jsonb_build_object('screen','dailyMoment');
 elsif prefix='hot' then
  select jsonb_build_object('screen','hotNews','id',h.id) into result from public.hot_news h join public.profiles p on p.phone=me where h.id=target and (h.district=p.district or p.is_super_admin);
 elsif n.post_id is not null then result:=jsonb_build_object('screen','home','postId',n.post_id);
 else result:=jsonb_build_object('screen',case when n.kind in ('friend_request','friend_accepted') then 'dailyMoment' else 'notifications' end); end if;
 update public.notifications set is_read=true where id=n.id and recipient_phone=me;
 return coalesce(result,jsonb_build_object('screen','notifications','unavailable',true));
end $$;
-- Public invokers expose only guarded private entrypoints.
create or replace function public.send_chat_message_verified(p_kind text,p_id uuid,p_body text,p_image_url text,p_client_id uuid) returns jsonb language sql security invoker set search_path='' as $$select app_private.send_chat_message_verified(p_kind,p_id,p_body,p_image_url,p_client_id)$$;
create or replace function public.mark_conversation_read_v423(p_phone text,p_kind text,p_id uuid,p_through timestamptz) returns jsonb language sql security invoker set search_path='' as $$select app_private.mark_conversation_read_v423(p_phone,p_kind,p_id,p_through)$$;
create or replace function public.resolve_notification(p_id uuid) returns jsonb language sql security invoker set search_path='' as $$select app_private.resolve_notification(p_id)$$;
revoke all on function public.send_chat_message_verified(text,uuid,text,text,uuid),app_private.send_chat_message_verified(text,uuid,text,text,uuid),public.mark_conversation_read_v423(text,text,uuid,timestamptz),app_private.mark_conversation_read_v423(text,text,uuid,timestamptz),public.resolve_notification(uuid),app_private.resolve_notification(uuid) from public,anon;
grant execute on function public.send_chat_message_verified(text,uuid,text,text,uuid),app_private.send_chat_message_verified(text,uuid,text,text,uuid),public.mark_conversation_read_v423(text,text,uuid,timestamptz),app_private.mark_conversation_read_v423(text,text,uuid,timestamptz),public.resolve_notification(uuid),app_private.resolve_notification(uuid) to authenticated;
create or replace function public.list_blocked_users(p_phone text)
returns table(phone text,full_name text) language plpgsql security definer set search_path=public as $$
begin perform app_private.assert_actor(p_phone); return query select p.phone,p.full_name from user_blocks b join profiles p on p.phone=b.blocked_phone
 where b.blocker_phone=regexp_replace(p_phone,'\D','','g') order by b.created_at desc; end;
$$;
create or replace function public.set_user_block(p_phone text,p_other_phone text,p_blocked boolean)
returns jsonb language plpgsql security definer set search_path=public as $$
declare a text:=regexp_replace(p_phone,'\D','','g');b text:=regexp_replace(p_other_phone,'\D','','g');
begin
 perform app_private.assert_actor(p_phone);
 if a=b or not exists(select 1 from profiles where phone=a) or not exists(select 1 from profiles where phone=b) then raise exception 'მომხმარებელი ვერ მოიძებნა';end if;
 if p_blocked then insert into user_blocks(blocker_phone,blocked_phone) values(a,b) on conflict do nothing;
 else delete from user_blocks where blocker_phone=a and blocked_phone=b;end if;
 return jsonb_build_object('ok',true);
end;$$;
create or replace function public.list_user_reports_admin(p_phone text)
returns table(id uuid,reported_name text,reporter_name text,category text,details text,status text,created_at timestamptz)
language plpgsql security definer set search_path=public as $$
begin
 perform app_private.assert_actor(p_phone);
 if not exists(select 1 from profiles where phone=regexp_replace(p_phone,'\D','','g') and is_super_admin is true) then raise exception 'ადმინისტრატორის უფლება საჭიროა';end if;
 return query select r.id,a.full_name,b.full_name,r.category,r.details,r.status,r.created_at from user_reports r join profiles a on a.phone=r.reported_phone join profiles b on b.phone=r.reporter_phone order by (r.status='open') desc,r.created_at desc limit 200;
end;$$;
create or replace function public.review_user_report(p_phone text,p_id uuid,p_status text)
returns jsonb language plpgsql security definer set search_path=public as $$
begin
 perform app_private.assert_actor(p_phone);
 if not exists(select 1 from profiles where phone=regexp_replace(p_phone,'\D','','g') and is_super_admin is true) then raise exception 'ადმინისტრატორის უფლება საჭიროა';end if;
 if p_status not in ('open','reviewing','resolved','dismissed') then raise exception 'არასწორი სტატუსი';end if;
 update user_reports set status=p_status where id=p_id;
 if not found then raise exception 'საჩივარი ვერ მოიძებნა';end if;
 return jsonb_build_object('ok',true);
end;$$;

revoke all on function public.list_blocked_users(text),public.set_user_block(text,text,boolean),public.list_user_reports_admin(text),public.review_user_report(text,uuid,text) from public,anon;
grant execute on function public.list_blocked_users(text),public.set_user_block(text,text,boolean),public.list_user_reports_admin(text),public.review_user_report(text,uuid,text) to authenticated;

notify pgrst,'reload schema';
commit;
