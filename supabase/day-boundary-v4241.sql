begin;
-- Display-only cutoff; no photo or calendar history is deleted.
create or replace function app_private.daily_visible_at(p_created timestamptz,p_now timestamptz)
returns boolean language sql immutable set search_path='' as $$
 select p_created >= ((p_now at time zone 'Asia/Tbilisi')::date::timestamp at time zone 'Asia/Tbilisi')
 and p_created <= p_now
 and (p_now at time zone 'Asia/Tbilisi')::time < time '23:59:00'
$$;
revoke all on function app_private.daily_visible_at(timestamptz,timestamptz) from public,anon,authenticated;
create or replace function app_private.legacy_has_recent_daily_moment(p_phone text)
returns boolean language sql security definer set search_path='' as $$
 select exists(select 1 from public.daily_moments d where d.phone=public.norm_daily_phone(p_phone)
 and d.owner_confirmed_at is not null and app_private.daily_visible_at(d.created_at,now()))
$$;
create or replace function app_private.legacy_list_daily_moments(p_phone text)
returns table(id uuid,phone text,full_name text,back_image_url text,front_image_url text,caption text,created_at timestamptz,locked boolean,liked_by_me boolean,like_count bigint,comment_count bigint)
language sql security definer set search_path='' as $$
 with me as(select public.norm_daily_phone(p_phone) p),unlocked as(select app_private.legacy_has_recent_daily_moment(p_phone) ok)
 select d.id,d.phone,p.full_name,d.back_image_url,d.front_image_url,d.caption,d.created_at,
 case when d.phone=me.p then false else not(select ok from unlocked) end,
 exists(select 1 from public.daily_moment_likes l where l.moment_id=d.id and l.phone=me.p),
 (select count(*) from public.daily_moment_likes l where l.moment_id=d.id),
 (select count(*) from public.daily_moment_comments c where c.moment_id=d.id)
 from public.daily_moments d join public.profiles p on p.phone=d.phone cross join me
 where d.owner_confirmed_at is not null and app_private.daily_visible_at(d.created_at,now())
 and (d.phone=me.p or exists(select 1 from public.daily_photo_friends f where f.user_phone=me.p and f.friend_phone=d.phone))
 order by(d.phone=me.p)desc,d.created_at desc
$$;
revoke all on function app_private.legacy_has_recent_daily_moment(text),app_private.legacy_list_daily_moments(text) from public,anon,authenticated;
notify pgrst,'reload schema';
commit;
