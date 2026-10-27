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
