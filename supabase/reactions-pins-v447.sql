set lock_timeout='3s';
set statement_timeout='20s';
alter table public.post_likes add column if not exists reaction text not null default '👍' check(reaction in('👍','❤️','😂','😮','😢','👏'));
alter table public.daily_moment_likes add column if not exists reaction text not null default '👍' check(reaction in('👍','❤️','😂','😮','😢','👏'));
create or replace function app_private.reaction_visible_v447(p_kind text,p_id uuid)returns boolean language plpgsql security definer set search_path='' as $$
declare actor text:=app_private.verified_phone();begin
 if p_kind='post'then return app_private.post_target(p_id)is not null;end if;
 if p_kind='daily'then return exists(select 1 from public.list_daily_moments(actor)d where d.id=p_id and not d.locked);end if;return false;end$$;
create or replace function app_private.reaction_summary_v447(p_kind text,p_id uuid)returns jsonb language plpgsql security definer set search_path='' as $$
declare actor text:=app_private.verified_phone();mine text;total bigint;counts jsonb;begin
 if not app_private.reaction_visible_v447(p_kind,p_id)then return null;end if;
 if p_kind='post'then
 select max(reaction)filter(where phone=actor),count(*)into mine,total from public.post_likes where post_id=p_id;
 select coalesce(jsonb_object_agg(reaction,n),'{}'::jsonb)into counts from(select reaction,count(*) n from public.post_likes where post_id=p_id group by reaction)x;
 else
 select max(reaction)filter(where phone=actor),count(*)into mine,total from public.daily_moment_likes where moment_id=p_id;
 select coalesce(jsonb_object_agg(reaction,n),'{}'::jsonb)into counts from(select reaction,count(*) n from public.daily_moment_likes where moment_id=p_id group by reaction)x;
 end if;return jsonb_build_object('id',p_id,'reaction',mine,'liked',mine is not null,'count',total,'counts',counts);end$$;
create or replace function app_private.set_reaction_v447(p_kind text,p_id uuid,p_reaction text)returns jsonb language plpgsql security definer set search_path='' as $$
declare actor text:=app_private.verified_phone();was_liked boolean;begin
 if p_reaction is not null and p_reaction not in('👍','❤️','😂','😮','😢','👏')then raise exception 'Invalid reaction' using errcode='22023';end if;
 if not app_private.reaction_visible_v447(p_kind,p_id)then raise exception 'Content unavailable'using errcode='42501';end if;
 perform pg_advisory_xact_lock(hashtextextended(actor||p_kind||p_id,0));
 if p_kind='post'then
 select exists(select 1 from public.post_likes where post_id=p_id and phone=actor)into was_liked;
 if p_reaction is null then delete from public.post_likes where post_id=p_id and phone=actor;
 elsif was_liked then update public.post_likes set reaction=p_reaction where post_id=p_id and phone=actor;
 else insert into public.post_likes(post_id,phone,reaction)values(p_id,actor,p_reaction);
 insert into public.notifications(recipient_phone,actor_phone,kind,title,body,post_id)select author_phone,actor,'post_like','შენს პოსტზე ახალი რეაქციაა',p_reaction,p_id from public.posts where id=p_id and author_phone<>actor;end if;
 else
 select exists(select 1 from public.daily_moment_likes where moment_id=p_id and phone=actor)into was_liked;
 if p_reaction is null then delete from public.daily_moment_likes where moment_id=p_id and phone=actor;
 elsif was_liked then update public.daily_moment_likes set reaction=p_reaction where moment_id=p_id and phone=actor;
 else insert into public.daily_moment_likes(moment_id,phone,reaction)values(p_id,actor,p_reaction);end if;
 end if;
 return app_private.reaction_summary_v447(p_kind,p_id)||jsonb_build_object('ok',true);
end$$;
create or replace function public.set_reaction_v447(p_kind text,p_id uuid,p_reaction text)returns jsonb language sql security invoker set search_path='' as $$select app_private.set_reaction_v447(p_kind,p_id,p_reaction)$$;
create or replace function app_private.reaction_summaries_v447(p_kind text,p_ids uuid[])returns jsonb language plpgsql security definer set search_path='' as $$
declare actor text:=app_private.verified_phone();result jsonb;begin
 if p_kind not in('post','daily')or coalesce(cardinality(p_ids),0)>100 then raise exception 'Invalid request';end if;
 select coalesce(jsonb_agg(value),'[]'::jsonb)into result from(select app_private.reaction_summary_v447(p_kind,id)value from(select distinct unnest(p_ids)id)x)y where value is not null;return result;end$$;
create or replace function public.reaction_summaries_v447(p_kind text,p_ids uuid[])returns jsonb language sql security invoker set search_path='' as $$select app_private.reaction_summaries_v447(p_kind,p_ids)$$;
-- Old clients keep their toggle behavior while sharing the same lock and visibility check.
create or replace function public.toggle_post_like(p_phone text,p_post_id uuid)returns jsonb language plpgsql security definer set search_path='' as $$begin
 perform app_private.assert_actor(p_phone);perform pg_advisory_xact_lock(hashtextextended(p_phone||'post'||p_post_id,0));
 return app_private.set_reaction_v447('post',p_post_id,case when exists(select 1 from public.post_likes where post_id=p_post_id and phone=p_phone)then null else '👍'end);end$$;
create or replace function public.toggle_daily_moment_like(p_phone text,p_moment_id uuid)returns jsonb language plpgsql security definer set search_path='' as $$begin
 perform app_private.assert_actor(p_phone);perform pg_advisory_xact_lock(hashtextextended(p_phone||'daily'||p_moment_id,0));
 return app_private.set_reaction_v447('daily',p_moment_id,case when exists(select 1 from public.daily_moment_likes where moment_id=p_moment_id and phone=p_phone)then null else '👍'end);end$$;
alter table public.live_chats add column if not exists pinned_message_id uuid references public.live_chat_messages(id) on delete set null;
create or replace function app_private.group_pin_allowed_v447(p_chat_id uuid)returns boolean language plpgsql security definer set search_path='' as $$
declare actor text:=app_private.verified_phone();begin
 if not exists(select 1 from public.live_chat_members where chat_id=p_chat_id and phone=actor)then return false;end if;
 return exists(select 1 from public.live_chats c join public.profiles owner on owner.phone=c.owner_phone where c.id=p_chat_id and app_private.staff_can_v433('posts',owner.city,array[owner.district]));end$$;
create or replace function app_private.group_pin_info_v447(p_chat_id uuid)returns jsonb language plpgsql security definer set search_path='' as $$
declare actor text:=app_private.verified_phone();result jsonb;begin
 if not exists(select 1 from public.live_chat_members where chat_id=p_chat_id and phone=actor)then raise exception 'Group unavailable'using errcode='42501';end if;
 select jsonb_build_object('can_pin',app_private.group_pin_allowed_v447(c.id),'message',case when m.id is null then null else jsonb_build_object('id',m.id,'body',left(coalesce(nullif(m.body,''),'დანართი'),240),'sender',m.sender_name)end)into result from public.live_chats c left join public.live_chat_messages m on m.id=c.pinned_message_id and m.chat_id=c.id where c.id=p_chat_id;return result;end$$;
create or replace function public.group_pin_info_v447(p_chat_id uuid)returns jsonb language sql security invoker set search_path='' as $$select app_private.group_pin_info_v447(p_chat_id)$$;
create or replace function app_private.set_group_pin_v447(p_chat_id uuid,p_message_id uuid,p_expected uuid)returns jsonb language plpgsql security definer set search_path='' as $$
declare actor text:=app_private.verified_phone();current_pin uuid;begin
 if not app_private.group_pin_allowed_v447(p_chat_id)then raise exception 'აპინვის უფლება არ გაქვს.'using errcode='42501';end if;
 select pinned_message_id into current_pin from public.live_chats where id=p_chat_id for update;
 if current_pin is distinct from p_expected then return jsonb_build_object('ok',false,'code','conflict');end if;
 if p_message_id is not null and not exists(select 1 from public.live_chat_messages where id=p_message_id and chat_id=p_chat_id)then raise exception 'Message unavailable'using errcode='42501';end if;
 update public.live_chats set pinned_message_id=p_message_id where id=p_chat_id;
 return app_private.group_pin_info_v447(p_chat_id)||jsonb_build_object('ok',true);end$$;
create or replace function public.set_group_pin_v447(p_chat_id uuid,p_message_id uuid,p_expected uuid)returns jsonb language sql security invoker set search_path='' as $$select app_private.set_group_pin_v447(p_chat_id,p_message_id,p_expected)$$;
revoke all on function app_private.reaction_visible_v447(text,uuid),app_private.reaction_summary_v447(text,uuid),app_private.group_pin_allowed_v447(uuid)from public,anon,authenticated;
revoke all on function app_private.set_reaction_v447(text,uuid,text),public.set_reaction_v447(text,uuid,text),app_private.reaction_summaries_v447(text,uuid[]),public.reaction_summaries_v447(text,uuid[]),app_private.group_pin_info_v447(uuid),public.group_pin_info_v447(uuid),app_private.set_group_pin_v447(uuid,uuid,uuid),public.set_group_pin_v447(uuid,uuid,uuid)from public,anon;
grant execute on function app_private.set_reaction_v447(text,uuid,text),public.set_reaction_v447(text,uuid,text),app_private.reaction_summaries_v447(text,uuid[]),public.reaction_summaries_v447(text,uuid[]),app_private.group_pin_info_v447(uuid),public.group_pin_info_v447(uuid),app_private.set_group_pin_v447(uuid,uuid,uuid),public.set_group_pin_v447(uuid,uuid,uuid)to authenticated;
notify pgrst,'reload schema';
