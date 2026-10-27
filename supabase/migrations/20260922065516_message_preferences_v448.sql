create table if not exists app_private.message_preferences_v448(phone text not null references public.profiles(phone) on delete cascade,kind text not null check(kind in('direct','group')),chat_id uuid not null,message_id uuid not null,hidden boolean not null default false,pinned boolean not null default false,primary key(phone,kind,chat_id,message_id));
alter table app_private.message_preferences_v448 enable row level security;
revoke all on app_private.message_preferences_v448 from public,anon,authenticated;
create or replace function app_private.message_preferences_v448(p_kind text,p_chat_id uuid,p_message_id uuid default null,p_action text default null)returns jsonb language plpgsql security definer set search_path='' as $$
declare actor text:=app_private.verified_phone(); result jsonb;begin
 perform app_private.assert_conversation(p_kind,p_chat_id);
 if p_action is not null then
 if p_action not in('hide','pin','unpin') or p_message_id is null or (p_action in('pin','unpin') and p_kind<>'direct') then raise exception 'Invalid action';end if;
 if p_kind='direct' then
 if not exists(select 1 from public.direct_chat_messages where id=p_message_id and thread_id=p_chat_id)then raise exception 'Message unavailable'using errcode='42501';end if;
 else
 if not exists(select 1 from public.live_chat_messages where id=p_message_id and chat_id=p_chat_id)then raise exception 'Message unavailable'using errcode='42501';end if;end if;
 perform pg_advisory_xact_lock(hashtextextended(actor||p_kind||p_chat_id,0));
 if p_action='pin'then update app_private.message_preferences_v448 set pinned=false where phone=actor and kind=p_kind and chat_id=p_chat_id;end if;
 insert into app_private.message_preferences_v448(phone,kind,chat_id,message_id,hidden,pinned)values(actor,p_kind,p_chat_id,p_message_id,p_action='hide',p_action='pin')on conflict(phone,kind,chat_id,message_id)do update set hidden=case when p_action='hide'then true else message_preferences_v448.hidden end,pinned=p_action='pin';
 end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',message_id,'hidden',hidden,'pinned',pinned)),'[]')into result from app_private.message_preferences_v448 where phone=actor and kind=p_kind and chat_id=p_chat_id;return result;
end$$;
create or replace function public.message_preferences_v448(p_kind text,p_chat_id uuid,p_message_id uuid default null,p_action text default null)returns jsonb language sql security invoker set search_path='' as $$select app_private.message_preferences_v448(p_kind,p_chat_id,p_message_id,p_action)$$;
revoke all on function app_private.message_preferences_v448(text,uuid,uuid,text),public.message_preferences_v448(text,uuid,uuid,text)from public,anon;
grant execute on function app_private.message_preferences_v448(text,uuid,uuid,text),public.message_preferences_v448(text,uuid,uuid,text)to authenticated;
notify pgrst,'reload schema';
