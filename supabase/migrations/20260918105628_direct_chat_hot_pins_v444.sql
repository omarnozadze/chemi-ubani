-- v444. No existing orders, messages or financial records are deleted.
set lock_timeout='3s';
set statement_timeout='20s';
alter table public.hot_news add column if not exists pinned boolean not null default false;
CREATE OR REPLACE FUNCTION app_private.list_hot_news()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare actor text:=app_private.verified_phone();result jsonb;begin
 select coalesce(jsonb_agg(to_jsonb(x)order by x.pinned desc,x.created_at desc,x.id desc),'[]'::jsonb)into result from(
 select h.id,h.title,h.body,h.category,h.district,h.city,h.neighborhood,h.image_url,h.created_at,h.campaign_id,h.pinned,app_private.staff_can_v433('news',h.city,array[h.district]) as can_pin from public.hot_news h
 join public.profiles p on p.phone=actor left join public.admin_campaigns c on c.id=h.campaign_id
 where(h.expires_at is null or h.expires_at>now())and(h.campaign_id is null or c.status='active')
 and ((p.is_super_admin or p.admin_level='super')or(h.district=p.district and(h.city is null or h.city=p.city)and(h.neighborhood is null or h.neighborhood=p.neighborhood)))
 order by h.pinned desc,h.created_at desc,h.id desc limit 100)x;return result;end $function$
;
create or replace function app_private.pin_hot_news_v444(p_id uuid,p_pinned boolean,p_expected boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor text:=app_private.verified_phone();h public.hot_news%rowtype;
begin
 select * into h from public.hot_news where id=p_id for update;
 if h.id is null or not app_private.staff_can_v433('news',h.city,array[h.district]) then raise exception 'აპინვის უფლება არ გაქვს.' using errcode='42501';end if;
 if p_pinned is null or p_expected is null then raise exception 'Invalid pin state';end if;
 if h.pinned<>p_expected then return jsonb_build_object('ok',false,'code','conflict');end if;
 update public.hot_news set pinned=p_pinned where id=p_id;
 insert into app_private.moderation_audit_v433(actor,kind,target,action) values(actor,'news',p_id,'pin');
 return jsonb_build_object('ok',true,'pinned',p_pinned);
end$$;
create or replace function public.pin_hot_news_v444(p_id uuid,p_pinned boolean,p_expected boolean)
returns jsonb language sql security invoker set search_path='' as $$select app_private.pin_hot_news_v444(p_id,p_pinned,p_expected)$$;
create or replace function app_private.start_specialist_chat_v444(p_ad_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor text:=app_private.verified_phone();ad public.specialist_announcements%rowtype;me public.profiles%rowtype;chat jsonb;
begin
 select * into ad from public.specialist_announcements where id=p_ad_id and status='approved';
 select * into me from public.profiles where phone=actor;
 if ad.id is null or me.phone is null or ad.owner_phone=actor or public.is_user_blocked(actor,ad.owner_phone) then raise exception 'სპეციალისტთან მიმოწერა მიუწვდომელია.' using errcode='42501';end if;
 if not(coalesce(me.is_super_admin,false)or coalesce(me.admin_level='super',false)) and (ad.city is distinct from me.city or not coalesce(me.district=any(ad.target_districts),false))then raise exception 'სპეციალისტი ამ რაიონში მიუწვდომელია.' using errcode='42501';end if;
 chat:=public.start_direct_chat(actor,ad.owner_phone);
 if chat->>'ok' is distinct from 'true' or chat->>'id' is null then raise exception 'მიმოწერა ვერ გაიხსნა.';end if;
 -- Opening a conversation never sends a message or creates an order on the user's behalf.
 return chat||jsonb_build_object('other',jsonb_build_object('phone',ad.owner_phone,'name',coalesce(ad.owner_name,'სპეციალისტი')));
end$$;
create or replace function public.start_specialist_chat_v444(p_ad_id uuid)
returns jsonb language sql security invoker set search_path='' as $$select app_private.start_specialist_chat_v444(p_ad_id)$$;
revoke all on function app_private.pin_hot_news_v444(uuid,boolean,boolean),public.pin_hot_news_v444(uuid,boolean,boolean),app_private.start_specialist_chat_v444(uuid),public.start_specialist_chat_v444(uuid) from public,anon;
grant execute on function app_private.pin_hot_news_v444(uuid,boolean,boolean),public.pin_hot_news_v444(uuid,boolean,boolean),app_private.start_specialist_chat_v444(uuid),public.start_specialist_chat_v444(uuid) to authenticated;
-- Payment integration is removed from the client and unavailable to API clients.
revoke all on function public.service_payment_status_v432(uuid),app_private.service_payment_status_v432(uuid) from public,anon,authenticated;
notify pgrst,'reload schema';
