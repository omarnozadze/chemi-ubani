-- v4.24.0: Verified-session guards, preserving legacy API argument/return contracts.
begin;

create or replace function app_private.assert_actor(p_phone text) returns void language plpgsql security definer set search_path='' as $$
begin
 if regexp_replace(coalesce(p_phone,''),'\D','','g') <> app_private.verified_phone() then raise exception 'Account mismatch' using errcode='42501'; end if;
end $$;
revoke all on function app_private.assert_actor(text) from public,anon,authenticated;
create or replace function app_private.require_admin() returns void language plpgsql security definer set search_path='' as $$
begin
 if not exists(select 1 from public.profiles where phone=app_private.verified_phone() and (is_super_admin or admin_level in ('super','admin'))) then raise exception 'Administrator required' using errcode='42501'; end if;
end $$;
revoke all on function app_private.require_admin() from public,anon,authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_add_daily_friend(p_phone text, p_friend_phone text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare a text:=public.norm_daily_phone(p_phone); b text:=public.norm_daily_phone(p_friend_phone);
begin
 if a=b or not exists(select 1 from profiles where phone=a) or not exists(select 1 from profiles where phone=b) then return jsonb_build_object('ok',false,'message','მომხმარებელი ვერ მოიძებნა'); end if;
 insert into daily_photo_friends(user_phone,friend_phone) values(a,b),(b,a) on conflict do nothing;
 return jsonb_build_object('ok',true);
end$function$
;

revoke all on function app_private.legacy_add_daily_friend(p_phone text, p_friend_phone text) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.add_daily_friend(p_phone text, p_friend_phone text)
 RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); return app_private.legacy_add_daily_friend(p_phone,p_friend_phone); end $guard$;
revoke all on function public.add_daily_friend(p_phone text, p_friend_phone text) from public,anon;
grant execute on function public.add_daily_friend(p_phone text, p_friend_phone text) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_add_daily_moment_comment(p_phone text, p_moment_id uuid, p_body text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v text:=public.norm_daily_phone(p_phone); i uuid;
begin if length(trim(coalesce(p_body,'')))<1 then return jsonb_build_object('ok',false,'message','კომენტარი ცარიელია');end if;insert into daily_moment_comments(moment_id,phone,body) values(p_moment_id,v,trim(p_body)) returning id into i;return jsonb_build_object('ok',true,'id',i);end$function$
;

revoke all on function app_private.legacy_add_daily_moment_comment(p_phone text, p_moment_id uuid, p_body text) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.add_daily_moment_comment(p_phone text, p_moment_id uuid, p_body text)
 RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); if not exists(select 1 from public.list_daily_moments(p_phone) d where d.id=p_moment_id and not d.locked) then raise exception 'Photo unavailable' using errcode='42501'; end if; return app_private.legacy_add_daily_moment_comment(p_phone,p_moment_id,p_body); end $guard$;
revoke all on function public.add_daily_moment_comment(p_phone text, p_moment_id uuid, p_body text) from public,anon;
grant execute on function public.add_daily_moment_comment(p_phone text, p_moment_id uuid, p_body text) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_add_live_chat_member(p_phone text, p_chat_id uuid, p_member_phone text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_phone text:=regexp_replace(coalesce(p_phone,''),'\D','','g');v_member text:=regexp_replace(coalesce(p_member_phone,''),'\D','','g');
begin
 if not exists(select 1 from public.live_chat_members where chat_id=p_chat_id and phone=v_phone and role in ('owner','admin')) then return jsonb_build_object('ok',false,'message','წევრის დამატების უფლება არ გაქვს'); end if;
 if not exists(select 1 from public.profiles where phone=v_member) then return jsonb_build_object('ok',false,'message','მომხმარებელი ვერ მოიძებნა'); end if;
 insert into public.live_chat_members(chat_id,phone,role) values(p_chat_id,v_member,'member') on conflict do nothing;
 return jsonb_build_object('ok',true);
end $function$
;

revoke all on function app_private.legacy_add_live_chat_member(p_phone text, p_chat_id uuid, p_member_phone text) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.add_live_chat_member(p_phone text, p_chat_id uuid, p_member_phone text)
 RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); return app_private.legacy_add_live_chat_member(p_phone,p_chat_id,p_member_phone); end $guard$;
revoke all on function public.add_live_chat_member(p_phone text, p_chat_id uuid, p_member_phone text) from public,anon;
grant execute on function public.add_live_chat_member(p_phone text, p_chat_id uuid, p_member_phone text) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_add_post_comment(p_phone text, p_post_id uuid, p_content text, p_parent_comment_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_phone text:=regexp_replace(coalesce(p_phone,''),'\D','','g'); v_name text; v_owner text; v_parent_owner text; v_id uuid;
begin
 if length(trim(coalesce(p_content,'')))=0 then return jsonb_build_object('ok',false,'message','კომენტარი ცარიელია'); end if;
 select full_name into v_name from public.profiles where phone=v_phone; if v_name is null then return jsonb_build_object('ok',false,'message','პროფილი ვერ მოიძებნა'); end if;
 select author_phone into v_owner from public.posts where id=p_post_id; if v_owner is null then return jsonb_build_object('ok',false,'message','პოსტი ვერ მოიძებნა'); end if;
 if p_parent_comment_id is not null then select author_phone into v_parent_owner from public.post_comments where id=p_parent_comment_id and post_id=p_post_id; if v_parent_owner is null then return jsonb_build_object('ok',false,'message','საწყისი კომენტარი ვერ მოიძებნა'); end if; end if;
 insert into public.post_comments(post_id,author_phone,author_name,content,parent_comment_id) values(p_post_id,v_phone,v_name,trim(p_content),p_parent_comment_id) returning id into v_id;
 if p_parent_comment_id is not null and v_parent_owner<>v_phone then insert into public.notifications(recipient_phone,actor_phone,kind,title,body,post_id,comment_id) values(v_parent_owner,v_phone,'reply','შენს კომენტარს უპასუხეს',v_name||': '||left(trim(p_content),90),p_post_id,v_id);
 elsif v_owner<>v_phone then insert into public.notifications(recipient_phone,actor_phone,kind,title,body,post_id,comment_id) values(v_owner,v_phone,'comment','ახალი კომენტარი შენს პოსტზე',v_name||': '||left(trim(p_content),90),p_post_id,v_id); end if;
 return jsonb_build_object('ok',true,'id',v_id,'author_name',v_name);
end $function$
;

revoke all on function app_private.legacy_add_post_comment(p_phone text, p_post_id uuid, p_content text, p_parent_comment_id uuid) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.add_post_comment(p_phone text, p_post_id uuid, p_content text, p_parent_comment_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); return app_private.legacy_add_post_comment(p_phone,p_post_id,p_content,p_parent_comment_id); end $guard$;
revoke all on function public.add_post_comment(p_phone text, p_post_id uuid, p_content text, p_parent_comment_id uuid) from public,anon;
grant execute on function public.add_post_comment(p_phone text, p_post_id uuid, p_content text, p_parent_comment_id uuid) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_admin_update_business_application_v420(p_phone text, p_id uuid, p_name text, p_category text, p_description text, p_address text, p_website text DEFAULT NULL::text, p_hours text DEFAULT NULL::text, p_image_url text DEFAULT NULL::text, p_lat double precision DEFAULT NULL::double precision, p_lng double precision DEFAULT NULL::double precision, p_application_type text DEFAULT 'free'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_type text:=lower(trim(coalesce(p_application_type,'free')));
begin
  if not public.can_manage_business_ads(p_phone) then return jsonb_build_object('ok',false,'message','ადმინისტრატორის უფლება საჭიროა'); end if;
  if length(trim(coalesce(p_name,'')))<2 or length(trim(coalesce(p_category,'')))<2 or length(trim(coalesce(p_address,'')))<2
  then return jsonb_build_object('ok',false,'message','სახელი, კატეგორია და მისამართი აუცილებელია'); end if;
  if v_type not in ('free','paid') then v_type:='free'; end if;
  update public.businesses set
    name=trim(p_name),category=trim(p_category),description=trim(coalesce(p_description,'')),address=trim(p_address),
    website=nullif(trim(coalesce(p_website,'')),''),hours=nullif(trim(coalesce(p_hours,'')),''),
    image_url=coalesce(nullif(trim(coalesce(p_image_url,'')),''),image_url),
    lat=coalesce(p_lat,lat),lng=coalesce(p_lng,lng),application_type=v_type,updated_at=now()
  where id=p_id;
  if not found then return jsonb_build_object('ok',false,'message','ბიზნესი ვერ მოიძებნა'); end if;
  return jsonb_build_object('ok',true);
end $function$
;

revoke all on function app_private.legacy_admin_update_business_application_v420(p_phone text, p_id uuid, p_name text, p_category text, p_description text, p_address text, p_website text, p_hours text, p_image_url text, p_lat double precision, p_lng double precision, p_application_type text) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.admin_update_business_application_v420(p_phone text, p_id uuid, p_name text, p_category text, p_description text, p_address text, p_website text DEFAULT NULL::text, p_hours text DEFAULT NULL::text, p_image_url text DEFAULT NULL::text, p_lat double precision DEFAULT NULL::double precision, p_lng double precision DEFAULT NULL::double precision, p_application_type text DEFAULT 'free'::text)
 RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); perform app_private.require_admin(); return app_private.legacy_admin_update_business_application_v420(p_phone,p_id,p_name,p_category,p_description,p_address,p_website,p_hours,p_image_url,p_lat,p_lng,p_application_type); end $guard$;
revoke all on function public.admin_update_business_application_v420(p_phone text, p_id uuid, p_name text, p_category text, p_description text, p_address text, p_website text, p_hours text, p_image_url text, p_lat double precision, p_lng double precision, p_application_type text) from public,anon;
grant execute on function public.admin_update_business_application_v420(p_phone text, p_id uuid, p_name text, p_category text, p_description text, p_address text, p_website text, p_hours text, p_image_url text, p_lat double precision, p_lng double precision, p_application_type text) to authenticated;

revoke all on function public.can_manage_business_ads(p_phone text) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_create_business_banner(p_phone text, p_business_id uuid, p_title text, p_image_url text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_phone text:=regexp_replace(coalesce(p_phone,''),'\D','','g');v_id uuid;
begin
 if not public.can_manage_business_ads(v_phone) then return jsonb_build_object('ok',false,'message','რეკლამის მართვის უფლება არ გაქვს'); end if;
 if not exists(select 1 from public.businesses where id=p_business_id and status='approved' and lat is not null and lng is not null) then return jsonb_build_object('ok',false,'message','აირჩიე დამტკიცებული ბიზნესი, რომელსაც მდებარეობა აქვს'); end if;
 if length(trim(coalesce(p_image_url,'')))<5 then return jsonb_build_object('ok',false,'message','ბანერის სურათი აუცილებელია'); end if;
 insert into public.business_banners(business_id,title,image_url,created_by) values(p_business_id,nullif(trim(coalesce(p_title,'')),''),trim(p_image_url),v_phone) returning id into v_id;
 return jsonb_build_object('ok',true,'id',v_id);
end $function$
;

revoke all on function app_private.legacy_create_business_banner(p_phone text, p_business_id uuid, p_title text, p_image_url text) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.create_business_banner(p_phone text, p_business_id uuid, p_title text, p_image_url text)
 RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); perform app_private.require_admin(); return app_private.legacy_create_business_banner(p_phone,p_business_id,p_title,p_image_url); end $guard$;
revoke all on function public.create_business_banner(p_phone text, p_business_id uuid, p_title text, p_image_url text) from public,anon;
grant execute on function public.create_business_banner(p_phone text, p_business_id uuid, p_title text, p_image_url text) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_create_daily_moment(p_phone text, p_back_url text, p_front_url text, p_caption text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_phone text:=public.norm_daily_phone(p_phone);
  v_id uuid;
  v_district text;
begin
  if not exists(select 1 from profiles where phone=v_phone) then
    return jsonb_build_object('ok',false,'message','პროფილი ვერ მოიძებნა');
  end if;
  if coalesce(trim(p_back_url),'')='' or coalesce(trim(p_front_url),'')='' then
    return jsonb_build_object('ok',false,'message','ორივე ფოტო საჭიროა');
  end if;

  select district into v_district from profiles where phone=v_phone;
  select id into v_id
  from daily_moments
  where phone=v_phone
    and (created_at at time zone 'Asia/Tbilisi')::date=(now() at time zone 'Asia/Tbilisi')::date
  limit 1;

  if v_id is null then
    insert into daily_moments(
      phone,back_image_url,front_image_url,caption,district,
      capture_mode,pair_captured_at,owner_confirmed_at
    )
    values(
      v_phone,p_back_url,p_front_url,nullif(trim(coalesce(p_caption,'')),''),
      v_district,'dual_auto',now(),now()
    )
    returning id into v_id;
  else
    update daily_moments
    set back_image_url=p_back_url,
        front_image_url=p_front_url,
        caption=nullif(trim(coalesce(p_caption,'')),''),
        capture_mode='dual_auto',
        pair_captured_at=now(),
        owner_confirmed_at=now(),
        updated_at=now()
    where id=v_id and phone=v_phone;
  end if;

  return jsonb_build_object('ok',true,'id',v_id,'owner_confirmed',true,'capture_mode','dual_auto');
end$function$
;

revoke all on function app_private.legacy_create_daily_moment(p_phone text, p_back_url text, p_front_url text, p_caption text) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.create_daily_moment(p_phone text, p_back_url text, p_front_url text, p_caption text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); return app_private.legacy_create_daily_moment(p_phone,p_back_url,p_front_url,p_caption); end $guard$;
revoke all on function public.create_daily_moment(p_phone text, p_back_url text, p_front_url text, p_caption text) from public,anon;
grant execute on function public.create_daily_moment(p_phone text, p_back_url text, p_front_url text, p_caption text) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_create_live_chat(p_phone text, p_name text, p_description text DEFAULT NULL::text, p_member_phones text[] DEFAULT '{}'::text[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_phone text:=regexp_replace(coalesce(p_phone,''),'\D','','g');
  v_id uuid;
  m text;
begin
  if not exists(select 1 from public.profiles where phone=v_phone) then
    return jsonb_build_object('ok',false,'message','პროფილი ვერ მოიძებნა');
  end if;
  if length(trim(coalesce(p_name,'')))=0 then
    return jsonb_build_object('ok',false,'message','ჩათის სახელი აუცილებელია');
  end if;
  insert into public.live_chats(owner_phone,name,description)
  values(v_phone,trim(p_name),nullif(trim(coalesce(p_description,'')),'')) returning id into v_id;
  insert into public.live_chat_members(chat_id,phone,role) values(v_id,v_phone,'owner');
  foreach m in array coalesce(p_member_phones,'{}'::text[]) loop
    m:=regexp_replace(coalesce(m,''),'\D','','g');
    if m<>'' and m<>v_phone and exists(select 1 from public.profiles where phone=m) then
      insert into public.live_chat_members(chat_id,phone,role) values(v_id,m,'member') on conflict do nothing;
    end if;
  end loop;
  return jsonb_build_object('ok',true,'id',v_id);
end $function$
;

revoke all on function app_private.legacy_create_live_chat(p_phone text, p_name text, p_description text, p_member_phones text[]) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.create_live_chat(p_phone text, p_name text, p_description text DEFAULT NULL::text, p_member_phones text[] DEFAULT '{}'::text[])
 RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); return app_private.legacy_create_live_chat(p_phone,p_name,p_description,p_member_phones); end $guard$;
revoke all on function public.create_live_chat(p_phone text, p_name text, p_description text, p_member_phones text[]) from public,anon;
grant execute on function public.create_live_chat(p_phone text, p_name text, p_description text, p_member_phones text[]) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_create_marketplace_listing(p_phone text, p_title text, p_description text, p_category text, p_price numeric DEFAULT 0, p_image_url text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_phone text:=regexp_replace(coalesce(p_phone,''),'\D','','g');v_p public.profiles%rowtype;v_id uuid;
begin
 select * into v_p from public.profiles where phone=v_phone limit 1;if not found then return jsonb_build_object('ok',false,'message','პროფილი ვერ მოიძებნა');end if;
 if length(trim(coalesce(p_title,'')))<2 or length(trim(coalesce(p_description,'')))<2 then return jsonb_build_object('ok',false,'message','სათაური და აღწერა აუცილებელია');end if;
 insert into public.marketplace_listings(owner_phone,owner_name,district,neighborhood,title,description,category,price,image_url)
 values(v_phone,v_p.full_name,v_p.district,v_p.neighborhood,trim(p_title),trim(p_description),coalesce(nullif(trim(p_category),''),'სხვა'),greatest(coalesce(p_price,0),0),nullif(trim(coalesce(p_image_url,'')),'')) returning id into v_id;
 return jsonb_build_object('ok',true,'id',v_id);
end $function$
;

revoke all on function app_private.legacy_create_marketplace_listing(p_phone text, p_title text, p_description text, p_category text, p_price numeric, p_image_url text) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.create_marketplace_listing(p_phone text, p_title text, p_description text, p_category text, p_price numeric DEFAULT 0, p_image_url text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); return app_private.legacy_create_marketplace_listing(p_phone,p_title,p_description,p_category,p_price,p_image_url); end $guard$;
revoke all on function public.create_marketplace_listing(p_phone text, p_title text, p_description text, p_category text, p_price numeric, p_image_url text) from public,anon;
grant execute on function public.create_marketplace_listing(p_phone text, p_title text, p_description text, p_category text, p_price numeric, p_image_url text) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_create_my_day_post(p_phone text, p_back_image_url text, p_front_image_url text, p_caption text DEFAULT NULL::text, p_tz_offset_minutes integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_me text:=regexp_replace(coalesce(p_phone,''),'\D','','g');
  v_day date := (now() - make_interval(mins=>coalesce(p_tz_offset_minutes,0)))::date;
  v_id uuid;
begin
  if not exists(select 1 from public.profiles where phone=v_me) then return jsonb_build_object('ok',false,'message','პროფილი ვერ მოიძებნა'); end if;
  if coalesce(trim(p_back_image_url),'')='' or coalesce(trim(p_front_image_url),'')='' then return jsonb_build_object('ok',false,'message','ორივე ფოტო საჭიროა'); end if;
  insert into public.my_day_posts(owner_phone,day_date,back_image_url,front_image_url,caption,tz_offset_minutes)
  values(v_me,v_day,p_back_image_url,p_front_image_url,nullif(trim(coalesce(p_caption,'')),''),coalesce(p_tz_offset_minutes,0))
  on conflict(owner_phone,day_date) do update set back_image_url=excluded.back_image_url,front_image_url=excluded.front_image_url,caption=excluded.caption,tz_offset_minutes=excluded.tz_offset_minutes,updated_at=now(),created_at=now()
  returning id into v_id;
  return jsonb_build_object('ok',true,'id',v_id,'day_date',v_day);
end $function$
;

revoke all on function app_private.legacy_create_my_day_post(p_phone text, p_back_image_url text, p_front_image_url text, p_caption text, p_tz_offset_minutes integer) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.create_my_day_post(p_phone text, p_back_image_url text, p_front_image_url text, p_caption text DEFAULT NULL::text, p_tz_offset_minutes integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); return app_private.legacy_create_my_day_post(p_phone,p_back_image_url,p_front_image_url,p_caption,p_tz_offset_minutes); end $guard$;
revoke all on function public.create_my_day_post(p_phone text, p_back_image_url text, p_front_image_url text, p_caption text, p_tz_offset_minutes integer) from public,anon;
grant execute on function public.create_my_day_post(p_phone text, p_back_image_url text, p_front_image_url text, p_caption text, p_tz_offset_minutes integer) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_create_post(p_phone text, p_type text, p_content text, p_image_url text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_phone text := regexp_replace(coalesce(p_phone,''), '\D', '', 'g');
  v_profile public.profiles%rowtype;
  v_post public.posts%rowtype;
begin
  if length(trim(coalesce(p_content,''))) = 0 then
    return jsonb_build_object('ok',false,'message','პოსტის ტექსტი ცარიელია');
  end if;

  select *
  into v_profile
  from public.profiles
  where phone = v_phone
  limit 1;

  if not found then
    return jsonb_build_object('ok',false,'message','პროფილი ვერ მოიძებნა');
  end if;

  if coalesce(v_profile.district,'') = ''
     and v_phone <> '500000000' then
    return jsonb_build_object('ok',false,'message','პროფილს რაიონი არ აქვს');
  end if;

  insert into public.posts(
    author_phone,
    author_name,
    district,
    neighborhood,
    type,
    content,
    image_url
  )
  values(
    v_phone,
    v_profile.full_name,
    coalesce(v_profile.district,'Super Admin'),
    v_profile.neighborhood,
    coalesce(nullif(trim(p_type),''),'პოსტი'),
    trim(p_content),
    nullif(trim(coalesce(p_image_url,'')),'')
  )
  returning * into v_post;

  return jsonb_build_object(
    'ok',true,
    'id',v_post.id,
    'district',v_post.district,
    'neighborhood',v_post.neighborhood,
    'created_at',v_post.created_at
  );
end;
$function$
;

revoke all on function app_private.legacy_create_post(p_phone text, p_type text, p_content text, p_image_url text) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.create_post(p_phone text, p_type text, p_content text, p_image_url text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); return app_private.legacy_create_post(p_phone,p_type,p_content,p_image_url); end $guard$;
revoke all on function public.create_post(p_phone text, p_type text, p_content text, p_image_url text) from public,anon;
grant execute on function public.create_post(p_phone text, p_type text, p_content text, p_image_url text) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_create_service_order(p_phone text, p_provider_phone text, p_provider_name text, p_category text, p_description text, p_address text, p_requested_time timestamp with time zone DEFAULT NULL::timestamp with time zone, p_starting_price numeric DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_phone text:=regexp_replace(coalesce(p_phone,''),'\D','','g');
  v_provider text:=regexp_replace(coalesce(p_provider_phone,''),'\D','','g');
  v_id uuid;
begin
  if v_phone='' or not exists(select 1 from public.profiles where phone=v_phone) then
    return jsonb_build_object('ok',false,'message','მომხმარებელი ვერ მოიძებნა');
  end if;
  if v_provider='' or not exists(select 1 from public.profiles where phone=v_provider) then
    return jsonb_build_object('ok',false,'message','სპეციალისტი ვერ მოიძებნა');
  end if;
  if v_phone=v_provider then return jsonb_build_object('ok',false,'message','საკუთარ თავთან შეკვეთას ვერ შექმნი'); end if;
  if length(trim(coalesce(p_description,'')))<3 then return jsonb_build_object('ok',false,'message','აღწერე სამუშაო'); end if;
  if length(trim(coalesce(p_address,'')))<3 then return jsonb_build_object('ok',false,'message','მიუთითე მისამართი'); end if;

  insert into public.service_orders(customer_phone,provider_phone,provider_name,category,description,address,requested_time,starting_price)
  values(v_phone,v_provider,trim(coalesce(p_provider_name,'სპეციალისტი')),trim(coalesce(p_category,'სერვისი')),trim(p_description),trim(p_address),p_requested_time,greatest(coalesce(p_starting_price,0),0))
  returning id into v_id;
  return jsonb_build_object('ok',true,'id',v_id,'status','consultation_requested');
end $function$
;

revoke all on function app_private.legacy_create_service_order(p_phone text, p_provider_phone text, p_provider_name text, p_category text, p_description text, p_address text, p_requested_time timestamp with time zone, p_starting_price numeric) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.create_service_order(p_phone text, p_provider_phone text, p_provider_name text, p_category text, p_description text, p_address text, p_requested_time timestamp with time zone DEFAULT NULL::timestamp with time zone, p_starting_price numeric DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); return app_private.legacy_create_service_order(p_phone,p_provider_phone,p_provider_name,p_category,p_description,p_address,p_requested_time,p_starting_price); end $guard$;
revoke all on function public.create_service_order(p_phone text, p_provider_phone text, p_provider_name text, p_category text, p_description text, p_address text, p_requested_time timestamp with time zone, p_starting_price numeric) from public,anon;
grant execute on function public.create_service_order(p_phone text, p_provider_phone text, p_provider_name text, p_category text, p_description text, p_address text, p_requested_time timestamp with time zone, p_starting_price numeric) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_customer_service_order_action(p_phone text, p_id uuid, p_action text, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
 v_phone text:=regexp_replace(coalesce(p_phone,''),'\D','','g');
 v public.service_orders%rowtype;
begin
 select * into v from public.service_orders where id=p_id and customer_phone=v_phone for update;
 if not found then return jsonb_build_object('ok',false,'message','შეკვეთა ვერ მოიძებნა ან უფლება არ გაქვს'); end if;

 if p_action='accept_offer' and v.status='offer_sent' and coalesce(v.final_price,0)>0 then
   -- Prototype: this only simulates escrow/hold. No real card charge happens here.
   update public.service_orders set status='funds_held',funds_held=true,updated_at=now() where id=p_id;
 elsif p_action='confirm_done' and v.status='work_done_pending' and v.funds_held then
   update public.service_orders
      set status='done',funds_held=false,commission=round((final_price*0.10)::numeric,2),payout=round((final_price*0.90)::numeric,2),completed_at=now(),updated_at=now()
    where id=p_id;
 elsif p_action='dispute' and v.status in ('funds_held','work_done_pending') then
   update public.service_orders set status='disputed',dispute_reason=nullif(trim(coalesce(p_reason,'')),''),updated_at=now() where id=p_id;
 elsif p_action='cancel' and v.status in ('consultation_requested','accepted','offer_sent') then
   update public.service_orders set status='cancelled',cancel_reason=nullif(trim(coalesce(p_reason,'')),''),updated_at=now() where id=p_id;
 else
   return jsonb_build_object('ok',false,'message','ამ ეტაპზე ეს მოქმედება შეუძლებელია');
 end if;
 return jsonb_build_object('ok',true);
end $function$
;

revoke all on function app_private.legacy_customer_service_order_action(p_phone text, p_id uuid, p_action text, p_reason text) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.customer_service_order_action(p_phone text, p_id uuid, p_action text, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); return app_private.legacy_customer_service_order_action(p_phone,p_id,p_action,p_reason); end $guard$;
revoke all on function public.customer_service_order_action(p_phone text, p_id uuid, p_action text, p_reason text) from public,anon;
grant execute on function public.customer_service_order_action(p_phone text, p_id uuid, p_action text, p_reason text) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_deactivate_business_banner(p_phone text, p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
 if not public.can_manage_business_ads(p_phone) then return jsonb_build_object('ok',false,'message','რეკლამის მართვის უფლება არ გაქვს'); end if;
 update public.business_banners set active=false where id=p_id;
 if not found then return jsonb_build_object('ok',false,'message','ბანერი ვერ მოიძებნა'); end if;
 return jsonb_build_object('ok',true);
end $function$
;

revoke all on function app_private.legacy_deactivate_business_banner(p_phone text, p_id uuid) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.deactivate_business_banner(p_phone text, p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); perform app_private.require_admin(); return app_private.legacy_deactivate_business_banner(p_phone,p_id); end $guard$;
revoke all on function public.deactivate_business_banner(p_phone text, p_id uuid) from public,anon;
grant execute on function public.deactivate_business_banner(p_phone text, p_id uuid) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_delete_marketplace_listing(p_phone text, p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_phone text:=regexp_replace(coalesce(p_phone,''),'\D','','g');v_super boolean:=false;
begin
 select coalesce(is_super_admin,false) into v_super from public.profiles where phone=v_phone;if v_phone='500000000' then v_super:=true;end if;
 delete from public.marketplace_listings where id=p_id and (owner_phone=v_phone or v_super);if not found then return jsonb_build_object('ok',false,'message','წაშლის უფლება არ გაქვს');end if;return jsonb_build_object('ok',true);
end $function$
;

revoke all on function app_private.legacy_delete_marketplace_listing(p_phone text, p_id uuid) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.delete_marketplace_listing(p_phone text, p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); return app_private.legacy_delete_marketplace_listing(p_phone,p_id); end $guard$;
revoke all on function public.delete_marketplace_listing(p_phone text, p_id uuid) from public,anon;
grant execute on function public.delete_marketplace_listing(p_phone text, p_id uuid) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_delete_post(p_phone text, p_post_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_phone text:=regexp_replace(coalesce(p_phone,''),'\D','','g'); v_super boolean:=false;
begin
 select coalesce(is_super_admin,false) into v_super from public.profiles where phone=v_phone; if v_phone='500000000' then v_super:=true; end if;
 delete from public.posts where id=p_post_id and (author_phone=v_phone or v_super);
 if not found then return jsonb_build_object('ok',false,'message','წაშლის უფლება არ გაქვს'); end if;
 return jsonb_build_object('ok',true);
end $function$
;

revoke all on function app_private.legacy_delete_post(p_phone text, p_post_id uuid) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.delete_post(p_phone text, p_post_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); return app_private.legacy_delete_post(p_phone,p_post_id); end $guard$;
revoke all on function public.delete_post(p_phone text, p_post_id uuid) from public,anon;
grant execute on function public.delete_post(p_phone text, p_post_id uuid) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_delete_specialist_announcement(p_phone text, p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_phone text:=regexp_replace(coalesce(p_phone,''),'\D','','g');v_super boolean:=false;
begin
 select coalesce(is_super_admin,false) into v_super from public.profiles where phone=v_phone;
 if v_phone='500000000' then v_super:=true; end if;
 delete from public.specialist_announcements where id=p_id and (owner_phone=v_phone or v_super);
 if not found then return jsonb_build_object('ok',false,'message','წაშლის უფლება არ გაქვს'); end if;
 return jsonb_build_object('ok',true);
end $function$
;

revoke all on function app_private.legacy_delete_specialist_announcement(p_phone text, p_id uuid) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.delete_specialist_announcement(p_phone text, p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); return app_private.legacy_delete_specialist_announcement(p_phone,p_id); end $guard$;
revoke all on function public.delete_specialist_announcement(p_phone text, p_id uuid) from public,anon;
grant execute on function public.delete_specialist_announcement(p_phone text, p_id uuid) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_ensure_profile_for_chat(p_phone text, p_full_name text, p_district text DEFAULT NULL::text, p_neighborhood text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_phone text:=regexp_replace(coalesce(p_phone,''),'\D','','g');
begin
 if length(v_phone)<6 then return jsonb_build_object('ok',false,'message','ტელეფონის ნომერი არასწორია'); end if;
 insert into public.profiles(phone,full_name,district,neighborhood)
 values(v_phone,coalesce(nullif(trim(p_full_name),''),'მომხმარებელი'),p_district,p_neighborhood)
 on conflict(phone) do update set
   full_name=case when coalesce(public.profiles.full_name,'')='' then excluded.full_name else public.profiles.full_name end,
   district=coalesce(public.profiles.district,excluded.district),
   neighborhood=coalesce(public.profiles.neighborhood,excluded.neighborhood);
 return jsonb_build_object('ok',true,'phone',v_phone);
end $function$
;

revoke all on function app_private.legacy_ensure_profile_for_chat(p_phone text, p_full_name text, p_district text, p_neighborhood text) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.ensure_profile_for_chat(p_phone text, p_full_name text, p_district text DEFAULT NULL::text, p_neighborhood text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); return app_private.legacy_ensure_profile_for_chat(p_phone,p_full_name,p_district,p_neighborhood); end $guard$;
revoke all on function public.ensure_profile_for_chat(p_phone text, p_full_name text, p_district text, p_neighborhood text) from public,anon;
grant execute on function public.ensure_profile_for_chat(p_phone text, p_full_name text, p_district text, p_neighborhood text) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_get_public_profile(p_viewer_phone text, p_profile_phone text)
 RETURNS TABLE(phone text, full_name text, district text, neighborhood text, avatar_url text, account_type text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_viewer text:=regexp_replace(coalesce(p_viewer_phone,''),'\D','','g');
  v_target text:=regexp_replace(coalesce(p_profile_phone,''),'\D','','g');
begin
  if not exists(select 1 from public.profiles where profiles.phone=v_viewer) then return; end if;
  return query
  select p.phone,p.full_name,p.district,p.neighborhood,p.avatar_url,p.account_type
  from public.profiles p
  where p.phone=v_target
  limit 1;
end $function$
;

revoke all on function app_private.legacy_get_public_profile(p_viewer_phone text, p_profile_phone text) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.get_public_profile(p_viewer_phone text, p_profile_phone text)
 RETURNS TABLE(phone text, full_name text, district text, neighborhood text, avatar_url text, account_type text)
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_viewer_phone); return query select * from app_private.legacy_get_public_profile(p_viewer_phone,p_profile_phone); end $guard$;
revoke all on function public.get_public_profile(p_viewer_phone text, p_profile_phone text) from public,anon;
grant execute on function public.get_public_profile(p_viewer_phone text, p_profile_phone text) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_get_public_user_profile(p_phone text, p_target_phone text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_target text:=regexp_replace(coalesce(p_target_phone,''),'\D','','g');
  p public.profiles%rowtype; v_done int:=0; v_cancel int:=0; v_total int:=0; v_rating numeric:=0;
begin
  select * into p from public.profiles where phone=v_target;
  if not found then return jsonb_build_object('ok',false,'message','მომხმარებელი ვერ მოიძებნა'); end if;
  select count(*)::int,
         count(*) filter(where status='done')::int,
         count(*) filter(where status='cancelled')::int
    into v_total,v_done,v_cancel from public.service_orders where provider_phone=v_target;
  select coalesce(round(avg(rating)::numeric,1),0) into v_rating from public.service_order_reviews where provider_phone=v_target;
  return jsonb_build_object(
    'ok',true,'phone',p.phone,'full_name',p.full_name,'district',p.district,'neighborhood',p.neighborhood,
    'account_type',p.account_type,'avatar_url',p.avatar_url,'is_super_admin',coalesce(p.is_super_admin,false),
    'orders_total',v_total,'orders_done',v_done,'orders_cancelled',v_cancel,'specialist_rating',v_rating
  );
end $function$
;

revoke all on function app_private.legacy_get_public_user_profile(p_phone text, p_target_phone text) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.get_public_user_profile(p_phone text, p_target_phone text)
 RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); return app_private.legacy_get_public_user_profile(p_phone,p_target_phone); end $guard$;
revoke all on function public.get_public_user_profile(p_phone text, p_target_phone text) from public,anon;
grant execute on function public.get_public_user_profile(p_phone text, p_target_phone text) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_get_user_block_state(p_phone text, p_other_phone text)
 RETURNS TABLE(i_blocked boolean, blocked_me boolean)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select
    exists(select 1 from public.user_blocks where blocker_phone=regexp_replace(coalesce(p_phone,''),'\D','','g') and blocked_phone=regexp_replace(coalesce(p_other_phone,''),'\D','','g')),
    exists(select 1 from public.user_blocks where blocker_phone=regexp_replace(coalesce(p_other_phone,''),'\D','','g') and blocked_phone=regexp_replace(coalesce(p_phone,''),'\D','','g'));
$function$
;

revoke all on function app_private.legacy_get_user_block_state(p_phone text, p_other_phone text) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.get_user_block_state(p_phone text, p_other_phone text)
 RETURNS TABLE(i_blocked boolean, blocked_me boolean)
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); return query select * from app_private.legacy_get_user_block_state(p_phone,p_other_phone); end $guard$;
revoke all on function public.get_user_block_state(p_phone text, p_other_phone text) from public,anon;
grant execute on function public.get_user_block_state(p_phone text, p_other_phone text) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_has_recent_daily_moment(p_phone text)
 RETURNS boolean
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$select exists(select 1 from daily_moments where phone=public.norm_daily_phone(p_phone) and created_at>=now()-interval '12 hours')$function$
;

revoke all on function app_private.legacy_has_recent_daily_moment(p_phone text) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.has_recent_daily_moment(p_phone text)
 RETURNS boolean
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); return app_private.legacy_has_recent_daily_moment(p_phone); end $guard$;
revoke all on function public.has_recent_daily_moment(p_phone text) from public,anon;
grant execute on function public.has_recent_daily_moment(p_phone text) to authenticated;

revoke all on function public.is_user_blocked(p_viewer_phone text, p_other_phone text) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_list_active_business_banners()
 RETURNS TABLE(id uuid, business_id uuid, business_name text, title text, image_url text, lat double precision, lng double precision)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
 select x.id,b.id,b.name,x.title,x.image_url,b.lat,b.lng
 from public.business_banners x join public.businesses b on b.id=x.business_id
 where x.active=true and b.status='approved' and b.lat is not null and b.lng is not null
 order by x.created_at desc limit 20;
$function$
;

revoke all on function app_private.legacy_list_active_business_banners() from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.list_active_business_banners()
 RETURNS TABLE(id uuid, business_id uuid, business_name text, title text, image_url text, lat double precision, lng double precision)
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.verified_phone(); return query select * from app_private.legacy_list_active_business_banners(); end $guard$;
revoke all on function public.list_active_business_banners() from public,anon;
grant execute on function public.list_active_business_banners() to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_list_business_banners_admin(p_phone text)
 RETURNS TABLE(id uuid, business_id uuid, business_name text, title text, image_url text, active boolean, created_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
 if not public.can_manage_business_ads(p_phone) then return; end if;
 return query select x.id,b.id,b.name,x.title,x.image_url,x.active,x.created_at from public.business_banners x join public.businesses b on b.id=x.business_id order by x.created_at desc limit 100;
end $function$
;

revoke all on function app_private.legacy_list_business_banners_admin(p_phone text) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.list_business_banners_admin(p_phone text)
 RETURNS TABLE(id uuid, business_id uuid, business_name text, title text, image_url text, active boolean, created_at timestamp with time zone)
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); perform app_private.require_admin(); return query select * from app_private.legacy_list_business_banners_admin(p_phone); end $guard$;
revoke all on function public.list_business_banners_admin(p_phone text) from public,anon;
grant execute on function public.list_business_banners_admin(p_phone text) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_list_businesses_admin(p_phone text)
 RETURNS TABLE(id uuid, owner_phone text, owner_name text, name text, category text, description text, address text, contact_phone text, status text, review_note text, is_premium boolean, premium_status text, created_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
 if not public.can_manage_business_ads(p_phone) then return; end if;
 return query select b.id,b.owner_phone,p.full_name,b.name,b.category,b.description,b.address,b.contact_phone,b.status,b.review_note,b.is_premium,pr.status,b.created_at
 from public.businesses b join public.profiles p on p.phone=b.owner_phone left join public.business_premium_requests pr on pr.business_id=b.id
 order by case b.status when 'pending' then 0 else 1 end,b.created_at desc;
end $function$
;

revoke all on function app_private.legacy_list_businesses_admin(p_phone text) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.list_businesses_admin(p_phone text)
 RETURNS TABLE(id uuid, owner_phone text, owner_name text, name text, category text, description text, address text, contact_phone text, status text, review_note text, is_premium boolean, premium_status text, created_at timestamp with time zone)
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); perform app_private.require_admin(); return query select * from app_private.legacy_list_businesses_admin(p_phone); end $guard$;
revoke all on function public.list_businesses_admin(p_phone text) from public,anon;
grant execute on function public.list_businesses_admin(p_phone text) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_list_businesses_admin_v420(p_phone text)
 RETURNS TABLE(id uuid, owner_phone text, owner_name text, name text, category text, description text, address text, website text, hours text, image_url text, lat double precision, lng double precision, application_type text, status text, review_note text, is_premium boolean, premium_status text, created_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.can_manage_business_ads(p_phone) then return; end if;
  return query
  select b.id,b.owner_phone,p.full_name,b.name,b.category,b.description,b.address,b.website,b.hours,b.image_url,
         b.lat,b.lng,b.application_type,b.status,b.review_note,b.is_premium,pr.status,b.created_at
  from public.businesses b
  join public.profiles p on p.phone=b.owner_phone
  left join public.business_premium_requests pr on pr.business_id=b.id
  order by case b.status when 'pending' then 0 when 'approved' then 1 else 2 end,b.created_at desc;
end $function$
;

revoke all on function app_private.legacy_list_businesses_admin_v420(p_phone text) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.list_businesses_admin_v420(p_phone text)
 RETURNS TABLE(id uuid, owner_phone text, owner_name text, name text, category text, description text, address text, website text, hours text, image_url text, lat double precision, lng double precision, application_type text, status text, review_note text, is_premium boolean, premium_status text, created_at timestamp with time zone)
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); perform app_private.require_admin(); return query select * from app_private.legacy_list_businesses_admin_v420(p_phone); end $guard$;
revoke all on function public.list_businesses_admin_v420(p_phone text) from public,anon;
grant execute on function public.list_businesses_admin_v420(p_phone text) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_list_daily_friend_candidates(p_phone text, p_search text)
 RETURNS TABLE(phone text, full_name text, district text, neighborhood text, avatar_url text, is_friend boolean)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
 with me as(select public.norm_daily_phone(p_phone) p),
      q as(select public.norm_daily_phone(p_search) s),
      rows as(
        select p.phone,p.full_name,p.district,p.neighborhood,p.avatar_url,
               exists(
                 select 1 from daily_photo_friends f,me
                 where f.user_phone=me.p and f.friend_phone=p.phone
               ) as is_friend
        from profiles p,me,q
        where p.phone<>me.p
          and length(q.s)>=6
          and p.phone like '%'||q.s||'%'
      )
 select phone,full_name,district,neighborhood,avatar_url,is_friend
 from rows
 order by is_friend desc, phone
 limit 40
$function$
;

revoke all on function app_private.legacy_list_daily_friend_candidates(p_phone text, p_search text) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.list_daily_friend_candidates(p_phone text, p_search text)
 RETURNS TABLE(phone text, full_name text, district text, neighborhood text, avatar_url text, is_friend boolean)
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); return query select * from app_private.legacy_list_daily_friend_candidates(p_phone,p_search); end $guard$;
revoke all on function public.list_daily_friend_candidates(p_phone text, p_search text) from public,anon;
grant execute on function public.list_daily_friend_candidates(p_phone text, p_search text) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_list_daily_friends(p_phone text)
 RETURNS TABLE(phone text, full_name text, district text, neighborhood text, avatar_url text)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
 with me as(select public.norm_daily_phone(p_phone) p)
 select p.phone,p.full_name,p.district,p.neighborhood,p.avatar_url
 from daily_photo_friends f
 join profiles p on p.phone=f.friend_phone,me
 where f.user_phone=me.p
 order by p.full_name nulls last,p.phone
$function$
;

revoke all on function app_private.legacy_list_daily_friends(p_phone text) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.list_daily_friends(p_phone text)
 RETURNS TABLE(phone text, full_name text, district text, neighborhood text, avatar_url text)
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); return query select * from app_private.legacy_list_daily_friends(p_phone); end $guard$;
revoke all on function public.list_daily_friends(p_phone text) from public,anon;
grant execute on function public.list_daily_friends(p_phone text) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_list_daily_moment_comments(p_phone text, p_moment_id uuid)
 RETURNS TABLE(id uuid, phone text, full_name text, body text, created_at timestamp with time zone)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$select c.id,c.phone,p.full_name,c.body,c.created_at from daily_moment_comments c join profiles p on p.phone=c.phone where c.moment_id=p_moment_id order by c.created_at$function$
;

revoke all on function app_private.legacy_list_daily_moment_comments(p_phone text, p_moment_id uuid) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.list_daily_moment_comments(p_phone text, p_moment_id uuid)
 RETURNS TABLE(id uuid, phone text, full_name text, body text, created_at timestamp with time zone)
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); if not exists(select 1 from public.list_daily_moments(p_phone) d where d.id=p_moment_id and not d.locked) then raise exception 'Photo unavailable' using errcode='42501'; end if; return query select * from app_private.legacy_list_daily_moment_comments(p_phone,p_moment_id); end $guard$;
revoke all on function public.list_daily_moment_comments(p_phone text, p_moment_id uuid) from public,anon;
grant execute on function public.list_daily_moment_comments(p_phone text, p_moment_id uuid) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_list_daily_moments(p_phone text)
 RETURNS TABLE(id uuid, phone text, full_name text, back_image_url text, front_image_url text, caption text, created_at timestamp with time zone, locked boolean, liked_by_me boolean, like_count bigint, comment_count bigint)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
 with me as(select public.norm_daily_phone(p_phone) p),
      unlocked as(
        select exists(
          select 1 from daily_moments d,me
          where d.phone=me.p
            and d.owner_confirmed_at is not null
            and d.created_at>=now()-interval '12 hours'
        ) ok
      )
 select d.id,d.phone,p.full_name,d.back_image_url,d.front_image_url,d.caption,d.created_at,
        case when d.phone=(select p from me) then false else not (select ok from unlocked) end,
        exists(select 1 from daily_moment_likes l,me where l.moment_id=d.id and l.phone=me.p),
        (select count(*) from daily_moment_likes l where l.moment_id=d.id),
        (select count(*) from daily_moment_comments c where c.moment_id=d.id)
 from daily_moments d
 join profiles p on p.phone=d.phone,me
 where d.owner_confirmed_at is not null
   and (d.phone=me.p or exists(
      select 1 from daily_photo_friends f
      where f.user_phone=me.p and f.friend_phone=d.phone
   ))
   and d.created_at>=now()-interval '36 hours'
 order by (d.phone=me.p) desc,d.created_at desc
$function$
;

revoke all on function app_private.legacy_list_daily_moments(p_phone text) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.list_daily_moments(p_phone text)
 RETURNS TABLE(id uuid, phone text, full_name text, back_image_url text, front_image_url text, caption text, created_at timestamp with time zone, locked boolean, liked_by_me boolean, like_count bigint, comment_count bigint)
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); return query select * from app_private.legacy_list_daily_moments(p_phone); end $guard$;
revoke all on function public.list_daily_moments(p_phone text) from public,anon;
grant execute on function public.list_daily_moments(p_phone text) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_list_direct_chats(p_phone text)
 RETURNS TABLE(id uuid, other_phone text, other_name text, other_avatar_url text, other_district text, last_message text, last_message_at timestamp with time zone, unread_count bigint, is_favorite boolean)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with me as(select regexp_replace(coalesce(p_phone,''),'\D','','g') phone)
  select t.id,p.phone,p.full_name,p.avatar_url,p.district,
    (select coalesce(nullif(m.body,''),'📷 ფოტო') from public.direct_chat_messages m where m.thread_id=t.id order by m.created_at desc limit 1),
    (select m.created_at from public.direct_chat_messages m where m.thread_id=t.id order by m.created_at desc limit 1),
    (select count(*) from public.direct_chat_messages m
      where m.thread_id=t.id and m.sender_phone<>me.phone
      and m.created_at>coalesce((select r.last_read_at from public.direct_chat_reads r where r.thread_id=t.id and r.phone=me.phone),t.created_at)),
    exists(select 1 from public.chat_favorites f where f.phone=me.phone and f.conversation_type='direct' and f.conversation_id=t.id)
  from public.direct_chat_threads t cross join me
  join public.profiles p on p.phone=case when t.user_a=me.phone then t.user_b else t.user_a end
  where me.phone in(t.user_a,t.user_b) and not public.is_user_blocked(me.phone,p.phone)
  order by exists(select 1 from public.chat_favorites f where f.phone=me.phone and f.conversation_type='direct' and f.conversation_id=t.id) desc,
    coalesce((select max(m.created_at) from public.direct_chat_messages m where m.thread_id=t.id),t.created_at) desc;
$function$
;

revoke all on function app_private.legacy_list_direct_chats(p_phone text) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.list_direct_chats(p_phone text)
 RETURNS TABLE(id uuid, other_phone text, other_name text, other_avatar_url text, other_district text, last_message text, last_message_at timestamp with time zone, unread_count bigint, is_favorite boolean)
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); return query select * from app_private.legacy_list_direct_chats(p_phone); end $guard$;
revoke all on function public.list_direct_chats(p_phone text) from public,anon;
grant execute on function public.list_direct_chats(p_phone text) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_list_direct_messages(p_phone text, p_thread_id uuid)
 RETURNS TABLE(id uuid, thread_id uuid, sender_phone text, sender_name text, body text, image_url text, created_at timestamp with time zone)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with me as(select regexp_replace(coalesce(p_phone,''),'\D','','g') phone)
  select m.id,m.thread_id,m.sender_phone,p.full_name,m.body,m.image_url,m.created_at
  from public.direct_chat_messages m join public.direct_chat_threads t on t.id=m.thread_id
  join public.profiles p on p.phone=m.sender_phone cross join me
  where m.thread_id=p_thread_id and me.phone in(t.user_a,t.user_b)
  order by m.created_at;
$function$
;

revoke all on function app_private.legacy_list_direct_messages(p_phone text, p_thread_id uuid) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.list_direct_messages(p_phone text, p_thread_id uuid)
 RETURNS TABLE(id uuid, thread_id uuid, sender_phone text, sender_name text, body text, image_url text, created_at timestamp with time zone)
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); return query select * from app_private.legacy_list_direct_messages(p_phone,p_thread_id); end $guard$;
revoke all on function public.list_direct_messages(p_phone text, p_thread_id uuid) from public,anon;
grant execute on function public.list_direct_messages(p_phone text, p_thread_id uuid) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_list_direct_messages_between(p_phone text, p_target_phone text)
 RETURNS TABLE(id uuid, sender_phone text, recipient_phone text, sender_name text, sender_avatar text, body text, created_at timestamp with time zone)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
 with x as (select regexp_replace(coalesce(p_phone,''),'\D','','g') a, regexp_replace(coalesce(p_target_phone,''),'\D','','g') b)
 select d.id,d.sender_phone,d.recipient_phone,p.full_name,p.avatar_url,d.body,d.created_at
 from public.direct_messages d join public.profiles p on p.phone=d.sender_phone,x
 where (d.sender_phone=x.a and d.recipient_phone=x.b) or (d.sender_phone=x.b and d.recipient_phone=x.a)
 order by d.created_at asc limit 500;
$function$
;

revoke all on function app_private.legacy_list_direct_messages_between(p_phone text, p_target_phone text) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.list_direct_messages_between(p_phone text, p_target_phone text)
 RETURNS TABLE(id uuid, sender_phone text, recipient_phone text, sender_name text, sender_avatar text, body text, created_at timestamp with time zone)
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); return query select * from app_private.legacy_list_direct_messages_between(p_phone,p_target_phone); end $guard$;
revoke all on function public.list_direct_messages_between(p_phone text, p_target_phone text) from public,anon;
grant execute on function public.list_direct_messages_between(p_phone text, p_target_phone text) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_list_live_chat_add_candidates(p_phone text, p_chat_id uuid)
 RETURNS TABLE(phone text, full_name text, district text, neighborhood text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_phone text:=regexp_replace(coalesce(p_phone,''),'\D','','g');
begin
 if not exists(select 1 from public.live_chat_members where chat_id=p_chat_id and phone=v_phone and role in ('owner','admin')) then return; end if;
 return query select p.phone,p.full_name,p.district,p.neighborhood from public.profiles p
 where p.phone<>v_phone and not exists(select 1 from public.live_chat_members m where m.chat_id=p_chat_id and m.phone=p.phone)
 order by p.full_name limit 300;
end $function$
;

revoke all on function app_private.legacy_list_live_chat_add_candidates(p_phone text, p_chat_id uuid) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.list_live_chat_add_candidates(p_phone text, p_chat_id uuid)
 RETURNS TABLE(phone text, full_name text, district text, neighborhood text)
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); return query select * from app_private.legacy_list_live_chat_add_candidates(p_phone,p_chat_id); end $guard$;
revoke all on function public.list_live_chat_add_candidates(p_phone text, p_chat_id uuid) from public,anon;
grant execute on function public.list_live_chat_add_candidates(p_phone text, p_chat_id uuid) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_list_live_chat_candidates(p_phone text)
 RETURNS TABLE(phone text, full_name text, district text, neighborhood text)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select p.phone,p.full_name,p.district,p.neighborhood
  from public.profiles p
  where p.phone<>regexp_replace(coalesce(p_phone,''),'\D','','g')
  order by p.full_name asc limit 300;
$function$
;

revoke all on function app_private.legacy_list_live_chat_candidates(p_phone text) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.list_live_chat_candidates(p_phone text)
 RETURNS TABLE(phone text, full_name text, district text, neighborhood text)
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); return query select * from app_private.legacy_list_live_chat_candidates(p_phone); end $guard$;
revoke all on function public.list_live_chat_candidates(p_phone text) from public,anon;
grant execute on function public.list_live_chat_candidates(p_phone text) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_list_live_chat_candidates_v420(p_phone text)
 RETURNS TABLE(phone text, full_name text, district text, neighborhood text, avatar_url text)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
 select p.phone,p.full_name,p.district,p.neighborhood,p.avatar_url
 from public.profiles p
 where p.phone<>regexp_replace(coalesce(p_phone,''),'\D','','g')
 order by p.full_name asc limit 300;
$function$
;

revoke all on function app_private.legacy_list_live_chat_candidates_v420(p_phone text) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.list_live_chat_candidates_v420(p_phone text)
 RETURNS TABLE(phone text, full_name text, district text, neighborhood text, avatar_url text)
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); return query select * from app_private.legacy_list_live_chat_candidates_v420(p_phone); end $guard$;
revoke all on function public.list_live_chat_candidates_v420(p_phone text) from public,anon;
grant execute on function public.list_live_chat_candidates_v420(p_phone text) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_list_live_chat_members(p_phone text, p_chat_id uuid)
 RETURNS TABLE(phone text, full_name text, role text)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select cm.phone,p.full_name,cm.role
  from public.live_chat_members cm
  join public.profiles p on p.phone=cm.phone
  where cm.chat_id=p_chat_id
    and exists(select 1 from public.live_chat_members me where me.chat_id=p_chat_id and me.phone=regexp_replace(coalesce(p_phone,''),'\D','','g'))
  order by case cm.role when 'owner' then 0 when 'admin' then 1 else 2 end,p.full_name;
$function$
;

revoke all on function app_private.legacy_list_live_chat_members(p_phone text, p_chat_id uuid) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.list_live_chat_members(p_phone text, p_chat_id uuid)
 RETURNS TABLE(phone text, full_name text, role text)
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); return query select * from app_private.legacy_list_live_chat_members(p_phone,p_chat_id); end $guard$;
revoke all on function public.list_live_chat_members(p_phone text, p_chat_id uuid) from public,anon;
grant execute on function public.list_live_chat_members(p_phone text, p_chat_id uuid) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_list_live_chat_members_v420(p_phone text, p_chat_id uuid)
 RETURNS TABLE(phone text, full_name text, role text, avatar_url text)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
 select cm.phone,p.full_name,cm.role,p.avatar_url
 from public.live_chat_members cm join public.profiles p on p.phone=cm.phone
 where cm.chat_id=p_chat_id and exists(select 1 from public.live_chat_members me where me.chat_id=p_chat_id and me.phone=regexp_replace(coalesce(p_phone,''),'\D','','g'))
 order by case cm.role when 'owner' then 0 when 'admin' then 1 else 2 end,p.full_name;
$function$
;

revoke all on function app_private.legacy_list_live_chat_members_v420(p_phone text, p_chat_id uuid) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.list_live_chat_members_v420(p_phone text, p_chat_id uuid)
 RETURNS TABLE(phone text, full_name text, role text, avatar_url text)
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); return query select * from app_private.legacy_list_live_chat_members_v420(p_phone,p_chat_id); end $guard$;
revoke all on function public.list_live_chat_members_v420(p_phone text, p_chat_id uuid) from public,anon;
grant execute on function public.list_live_chat_members_v420(p_phone text, p_chat_id uuid) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_list_live_chat_messages(p_phone text, p_chat_id uuid)
 RETURNS TABLE(id uuid, chat_id uuid, sender_phone text, sender_name text, body text, image_url text, created_at timestamp with time zone)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
select * from (select m.id,m.chat_id,m.sender_phone,m.sender_name,m.body,m.image_url,m.created_at
  from public.live_chat_messages m
  where m.chat_id=p_chat_id
    and exists(
      select 1 from public.live_chat_members cm
      where cm.chat_id=p_chat_id and cm.phone=regexp_replace(coalesce(p_phone,''),'\D','','g')
    )
  order by m.created_at desc limit 500) recent order by created_at asc;
$function$
;

revoke all on function app_private.legacy_list_live_chat_messages(p_phone text, p_chat_id uuid) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.list_live_chat_messages(p_phone text, p_chat_id uuid)
 RETURNS TABLE(id uuid, chat_id uuid, sender_phone text, sender_name text, body text, image_url text, created_at timestamp with time zone)
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); return query select * from app_private.legacy_list_live_chat_messages(p_phone,p_chat_id); end $guard$;
revoke all on function public.list_live_chat_messages(p_phone text, p_chat_id uuid) from public,anon;
grant execute on function public.list_live_chat_messages(p_phone text, p_chat_id uuid) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_list_live_chat_messages_v420(p_phone text, p_chat_id uuid)
 RETURNS TABLE(id uuid, sender_phone text, sender_name text, sender_avatar text, body text, image_url text, created_at timestamp with time zone)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
select * from (select m.id,m.sender_phone,m.sender_name,p.avatar_url,m.body,m.image_url,m.created_at
 from public.live_chat_messages m join public.profiles p on p.phone=m.sender_phone
 where m.chat_id=p_chat_id and exists(select 1 from public.live_chat_members me where me.chat_id=p_chat_id and me.phone=regexp_replace(coalesce(p_phone,''),'\D','','g'))
 order by m.created_at desc limit 500) recent order by created_at asc;
$function$
;

revoke all on function app_private.legacy_list_live_chat_messages_v420(p_phone text, p_chat_id uuid) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.list_live_chat_messages_v420(p_phone text, p_chat_id uuid)
 RETURNS TABLE(id uuid, sender_phone text, sender_name text, sender_avatar text, body text, image_url text, created_at timestamp with time zone)
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); return query select * from app_private.legacy_list_live_chat_messages_v420(p_phone,p_chat_id); end $guard$;
revoke all on function public.list_live_chat_messages_v420(p_phone text, p_chat_id uuid) from public,anon;
grant execute on function public.list_live_chat_messages_v420(p_phone text, p_chat_id uuid) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_list_live_chats_for_phone(p_phone text)
 RETURNS TABLE(id uuid, name text, description text, photo_url text, owner_phone text, my_role text, member_count bigint, last_message text, last_message_at timestamp with time zone, unread_count bigint, is_favorite boolean)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select c.id,c.name,c.description,c.photo_url,c.owner_phone,m.role,
    (select count(*) from public.live_chat_members cm where cm.chat_id=c.id),
    (select coalesce(nullif(lm.body,''),'📷 ფოტო') from public.live_chat_messages lm where lm.chat_id=c.id order by lm.created_at desc limit 1),
    (select lm.created_at from public.live_chat_messages lm where lm.chat_id=c.id order by lm.created_at desc limit 1),
    (select count(*) from public.live_chat_messages x where x.chat_id=c.id and x.sender_phone<>m.phone and x.created_at>m.last_read_at),
    exists(select 1 from public.chat_favorites f where f.phone=m.phone and f.conversation_type='group' and f.conversation_id=c.id)
  from public.live_chats c join public.live_chat_members m on m.chat_id=c.id
  where m.phone=regexp_replace(coalesce(p_phone,''),'\D','','g')
  order by exists(select 1 from public.chat_favorites f where f.phone=m.phone and f.conversation_type='group' and f.conversation_id=c.id) desc,
    coalesce((select max(x.created_at) from public.live_chat_messages x where x.chat_id=c.id),c.created_at) desc;
$function$
;

revoke all on function app_private.legacy_list_live_chats_for_phone(p_phone text) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.list_live_chats_for_phone(p_phone text)
 RETURNS TABLE(id uuid, name text, description text, photo_url text, owner_phone text, my_role text, member_count bigint, last_message text, last_message_at timestamp with time zone, unread_count bigint, is_favorite boolean)
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); return query select * from app_private.legacy_list_live_chats_for_phone(p_phone); end $guard$;
revoke all on function public.list_live_chats_for_phone(p_phone text) from public,anon;
grant execute on function public.list_live_chats_for_phone(p_phone text) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_list_marketplace(p_phone text)
 RETURNS TABLE(id uuid, owner_phone text, owner_name text, district text, neighborhood text, title text, description text, category text, price numeric, image_url text, status text, created_at timestamp with time zone)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
 select m.id,m.owner_phone,m.owner_name,m.district,m.neighborhood,m.title,m.description,m.category,m.price,m.image_url,m.status,m.created_at
 from public.marketplace_listings m
 where m.status='active'
 order by m.created_at desc limit 500;
$function$
;

revoke all on function app_private.legacy_list_marketplace(p_phone text) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.list_marketplace(p_phone text)
 RETURNS TABLE(id uuid, owner_phone text, owner_name text, district text, neighborhood text, title text, description text, category text, price numeric, image_url text, status text, created_at timestamp with time zone)
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); return query select * from app_private.legacy_list_marketplace(p_phone); end $guard$;
revoke all on function public.list_marketplace(p_phone text) from public,anon;
grant execute on function public.list_marketplace(p_phone text) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_list_my_businesses(p_phone text)
 RETURNS TABLE(id uuid, name text, category text, description text, address text, contact_phone text, website text, hours text, image_url text, lat double precision, lng double precision, status text, review_note text, is_premium boolean, created_at timestamp with time zone)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
 select b.id,b.name,b.category,b.description,b.address,b.contact_phone,b.website,b.hours,b.image_url,b.lat,b.lng,b.status,b.review_note,b.is_premium,b.created_at from public.businesses b where b.owner_phone=regexp_replace(coalesce(p_phone,''),'\D','','g') order by b.created_at desc;
$function$
;

revoke all on function app_private.legacy_list_my_businesses(p_phone text) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.list_my_businesses(p_phone text)
 RETURNS TABLE(id uuid, name text, category text, description text, address text, contact_phone text, website text, hours text, image_url text, lat double precision, lng double precision, status text, review_note text, is_premium boolean, created_at timestamp with time zone)
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); return query select * from app_private.legacy_list_my_businesses(p_phone); end $guard$;
revoke all on function public.list_my_businesses(p_phone text) from public,anon;
grant execute on function public.list_my_businesses(p_phone text) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_list_my_daily_memories(p_phone text)
 RETURNS TABLE(id uuid, back_image_url text, front_image_url text, caption text, created_at timestamp with time zone)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
 select d.id,d.back_image_url,d.front_image_url,d.caption,d.created_at
 from daily_moments d
 where d.phone=public.norm_daily_phone(p_phone)
   and d.owner_confirmed_at is not null
 order by d.created_at asc
$function$
;

revoke all on function app_private.legacy_list_my_daily_memories(p_phone text) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.list_my_daily_memories(p_phone text)
 RETURNS TABLE(id uuid, back_image_url text, front_image_url text, caption text, created_at timestamp with time zone)
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); return query select * from app_private.legacy_list_my_daily_memories(p_phone); end $guard$;
revoke all on function public.list_my_daily_memories(p_phone text) from public,anon;
grant execute on function public.list_my_daily_memories(p_phone text) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_list_my_day_calendar(p_phone text)
 RETURNS TABLE(day_date date)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select d.day_date from public.my_day_posts d where d.owner_phone=regexp_replace(coalesce(p_phone,''),'\D','','g') order by d.day_date desc limit 730;
$function$
;

revoke all on function app_private.legacy_list_my_day_calendar(p_phone text) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.list_my_day_calendar(p_phone text)
 RETURNS TABLE(day_date date)
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); return query select * from app_private.legacy_list_my_day_calendar(p_phone); end $guard$;
revoke all on function public.list_my_day_calendar(p_phone text) from public,anon;
grant execute on function public.list_my_day_calendar(p_phone text) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_list_my_day_feed(p_phone text)
 RETURNS TABLE(id uuid, owner_phone text, owner_name text, avatar_url text, day_date date, back_image_url text, front_image_url text, caption text, created_at timestamp with time zone, is_mine boolean)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with me as(select regexp_replace(coalesce(p_phone,''),'\D','','g') phone), allowed as(
    select phone from me
    union
    select case when f.requester_phone=me.phone then f.addressee_phone else f.requester_phone end
    from public.my_day_friendships f,me where f.status='accepted' and (f.requester_phone=me.phone or f.addressee_phone=me.phone)
  )
  select d.id,d.owner_phone,p.full_name,p.avatar_url,d.day_date,d.back_image_url,d.front_image_url,d.caption,d.created_at,(d.owner_phone=(select phone from me))
  from public.my_day_posts d join allowed a on a.phone=d.owner_phone join public.profiles p on p.phone=d.owner_phone
  order by d.created_at desc limit 100;
$function$
;

revoke all on function app_private.legacy_list_my_day_feed(p_phone text) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.list_my_day_feed(p_phone text)
 RETURNS TABLE(id uuid, owner_phone text, owner_name text, avatar_url text, day_date date, back_image_url text, front_image_url text, caption text, created_at timestamp with time zone, is_mine boolean)
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); return query select * from app_private.legacy_list_my_day_feed(p_phone); end $guard$;
revoke all on function public.list_my_day_feed(p_phone text) from public,anon;
grant execute on function public.list_my_day_feed(p_phone text) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_list_my_day_friend_requests(p_phone text)
 RETURNS TABLE(phone text, full_name text, avatar_url text, created_at timestamp with time zone)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select p.phone,p.full_name,p.avatar_url,f.created_at
  from public.my_day_friendships f join public.profiles p on p.phone=f.requester_phone
  where f.addressee_phone=regexp_replace(coalesce(p_phone,''),'\D','','g') and f.status='pending'
  order by f.created_at desc;
$function$
;

revoke all on function app_private.legacy_list_my_day_friend_requests(p_phone text) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.list_my_day_friend_requests(p_phone text)
 RETURNS TABLE(phone text, full_name text, avatar_url text, created_at timestamp with time zone)
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); return query select * from app_private.legacy_list_my_day_friend_requests(p_phone); end $guard$;
revoke all on function public.list_my_day_friend_requests(p_phone text) from public,anon;
grant execute on function public.list_my_day_friend_requests(p_phone text) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_list_my_day_friends(p_phone text)
 RETURNS TABLE(phone text, full_name text, avatar_url text, district text)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with me as(select regexp_replace(coalesce(p_phone,''),'\D','','g') phone), peers as(
    select case when f.requester_phone=me.phone then f.addressee_phone else f.requester_phone end phone
    from public.my_day_friendships f,me
    where f.status='accepted' and (f.requester_phone=me.phone or f.addressee_phone=me.phone)
  )
  select p.phone,p.full_name,p.avatar_url,p.district from peers x join public.profiles p using(phone) order by p.full_name;
$function$
;

revoke all on function app_private.legacy_list_my_day_friends(p_phone text) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.list_my_day_friends(p_phone text)
 RETURNS TABLE(phone text, full_name text, avatar_url text, district text)
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); return query select * from app_private.legacy_list_my_day_friends(p_phone); end $guard$;
revoke all on function public.list_my_day_friends(p_phone text) from public,anon;
grant execute on function public.list_my_day_friends(p_phone text) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_list_my_service_orders(p_phone text)
 RETURNS TABLE(id uuid, customer_phone text, provider_phone text, provider_name text, category text, description text, address text, requested_time timestamp with time zone, starting_price numeric, final_price numeric, status text, cancel_reason text, dispute_reason text, funds_held boolean, commission numeric, payout numeric, created_at timestamp with time zone, updated_at timestamp with time zone, completed_at timestamp with time zone, rating integer, review_comment text)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
 select o.id,o.customer_phone,o.provider_phone,o.provider_name,o.category,o.description,o.address,
        o.requested_time,o.starting_price,o.final_price,o.status,o.cancel_reason,o.dispute_reason,
        o.funds_held,o.commission,o.payout,o.created_at,o.updated_at,o.completed_at,
        r.rating,r.comment
 from public.service_orders o
 left join public.service_order_reviews r on r.order_id=o.id
 where o.customer_phone=regexp_replace(coalesce(p_phone,''),'\D','','g')
 order by o.created_at desc limit 200;
$function$
;

revoke all on function app_private.legacy_list_my_service_orders(p_phone text) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.list_my_service_orders(p_phone text)
 RETURNS TABLE(id uuid, customer_phone text, provider_phone text, provider_name text, category text, description text, address text, requested_time timestamp with time zone, starting_price numeric, final_price numeric, status text, cancel_reason text, dispute_reason text, funds_held boolean, commission numeric, payout numeric, created_at timestamp with time zone, updated_at timestamp with time zone, completed_at timestamp with time zone, rating integer, review_comment text)
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); return query select * from app_private.legacy_list_my_service_orders(p_phone); end $guard$;
revoke all on function public.list_my_service_orders(p_phone text) from public,anon;
grant execute on function public.list_my_service_orders(p_phone text) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_list_my_specialist_announcements(p_phone text)
 RETURNS TABLE(id uuid, owner_phone text, owner_name text, contact_phone text, title text, body text, price numeric, image_url text, target_districts text[], work_hours text, status text, review_note text, created_at timestamp with time zone, reviewed_at timestamp with time zone)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
 select a.id,a.owner_phone,a.owner_name,a.contact_phone,a.title,a.body,a.price,a.image_url,a.target_districts,a.work_hours,a.status,a.review_note,a.created_at,a.reviewed_at
 from public.specialist_announcements a
 where a.owner_phone=regexp_replace(coalesce(p_phone,''),'\D','','g')
 order by a.created_at desc;
$function$
;

revoke all on function app_private.legacy_list_my_specialist_announcements(p_phone text) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.list_my_specialist_announcements(p_phone text)
 RETURNS TABLE(id uuid, owner_phone text, owner_name text, contact_phone text, title text, body text, price numeric, image_url text, target_districts text[], work_hours text, status text, review_note text, created_at timestamp with time zone, reviewed_at timestamp with time zone)
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); return query select * from app_private.legacy_list_my_specialist_announcements(p_phone); end $guard$;
revoke all on function public.list_my_specialist_announcements(p_phone text) from public,anon;
grant execute on function public.list_my_specialist_announcements(p_phone text) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_list_notifications_for_phone(p_phone text)
 RETURNS TABLE(id uuid, kind text, title text, body text, post_id uuid, comment_id uuid, is_read boolean, created_at timestamp with time zone)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
 select n.id,n.kind,n.title,n.body,n.post_id,n.comment_id,n.is_read,n.created_at from public.notifications n
 where n.recipient_phone=regexp_replace(coalesce(p_phone,''),'\D','','g') order by n.created_at desc limit 100;
$function$
;

revoke all on function app_private.legacy_list_notifications_for_phone(p_phone text) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.list_notifications_for_phone(p_phone text)
 RETURNS TABLE(id uuid, kind text, title text, body text, post_id uuid, comment_id uuid, is_read boolean, created_at timestamp with time zone)
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); return query select * from app_private.legacy_list_notifications_for_phone(p_phone); end $guard$;
revoke all on function public.list_notifications_for_phone(p_phone text) from public,anon;
grant execute on function public.list_notifications_for_phone(p_phone text) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_list_paid_business_promotions(p_phone text)
 RETURNS TABLE(id uuid, name text, category text, description text, address text, image_url text, lat double precision, lng double precision, created_at timestamp with time zone)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select b.id,b.name,b.category,b.description,b.address,b.image_url,b.lat,b.lng,b.created_at
  from public.businesses b where b.status='approved' and b.application_type='paid'
  order by b.updated_at desc limit 50;
$function$
;

revoke all on function app_private.legacy_list_paid_business_promotions(p_phone text) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.list_paid_business_promotions(p_phone text)
 RETURNS TABLE(id uuid, name text, category text, description text, address text, image_url text, lat double precision, lng double precision, created_at timestamp with time zone)
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); return query select * from app_private.legacy_list_paid_business_promotions(p_phone); end $guard$;
revoke all on function public.list_paid_business_promotions(p_phone text) from public,anon;
grant execute on function public.list_paid_business_promotions(p_phone text) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_list_post_comments(p_phone text, p_post_id uuid)
 RETURNS TABLE(id uuid, post_id uuid, parent_comment_id uuid, author_phone text, author_name text, content text, created_at timestamp with time zone, like_count bigint, liked boolean)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
 select c.id,c.post_id,c.parent_comment_id,c.author_phone,c.author_name,c.content,c.created_at,
   (select count(*) from public.comment_likes l where l.comment_id=c.id),
   exists(select 1 from public.comment_likes l where l.comment_id=c.id and l.phone=regexp_replace(coalesce(p_phone,''),'\D','','g'))
 from public.post_comments c where c.post_id=p_post_id order by c.created_at asc;
$function$
;

revoke all on function app_private.legacy_list_post_comments(p_phone text, p_post_id uuid) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.list_post_comments(p_phone text, p_post_id uuid)
 RETURNS TABLE(id uuid, post_id uuid, parent_comment_id uuid, author_phone text, author_name text, content text, created_at timestamp with time zone, like_count bigint, liked boolean)
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); return query select * from app_private.legacy_list_post_comments(p_phone,p_post_id); end $guard$;
revoke all on function public.list_post_comments(p_phone text, p_post_id uuid) from public,anon;
grant execute on function public.list_post_comments(p_phone text, p_post_id uuid) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_list_posts_for_phone(p_phone text)
 RETURNS TABLE(id uuid, author_phone text, author_name text, district text, neighborhood text, type text, content text, image_url text, created_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_phone text := regexp_replace(coalesce(p_phone,''), '\D', '', 'g');
  v_district text;
  v_super boolean := false;
begin
  select p.district, coalesce(p.is_super_admin,false)
  into v_district, v_super
  from public.profiles p
  where p.phone = v_phone
  limit 1;

  if v_phone = '500000000' then
    v_super := true;
  end if;

  if v_super then
    return query
    select
      p.id,p.author_phone,p.author_name,p.district,
      p.neighborhood,p.type,p.content,p.image_url,p.created_at
    from public.posts p
    order by p.created_at desc
    limit 200;
  else
    return query
    select
      p.id,p.author_phone,p.author_name,p.district,
      p.neighborhood,p.type,p.content,p.image_url,p.created_at
    from public.posts p
    where p.district = v_district
    order by p.created_at desc
    limit 200;
  end if;
end;
$function$
;

revoke all on function app_private.legacy_list_posts_for_phone(p_phone text) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.list_posts_for_phone(p_phone text)
 RETURNS TABLE(id uuid, author_phone text, author_name text, district text, neighborhood text, type text, content text, image_url text, created_at timestamp with time zone)
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); return query select * from app_private.legacy_list_posts_for_phone(p_phone); end $guard$;
revoke all on function public.list_posts_for_phone(p_phone text) from public,anon;
grant execute on function public.list_posts_for_phone(p_phone text) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_list_posts_social_for_phone(p_phone text)
 RETURNS TABLE(id uuid, author_phone text, author_name text, district text, neighborhood text, type text, content text, image_url text, created_at timestamp with time zone, like_count bigint, comment_count bigint, liked boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_phone text:=regexp_replace(coalesce(p_phone,''),'\D','','g'); v_district text; v_super boolean:=false;
begin
 select p.district,coalesce(p.is_super_admin,false) into v_district,v_super from public.profiles p where p.phone=v_phone limit 1;
 if v_phone='500000000' then v_super:=true; end if;
 return query
 select p.id,p.author_phone,p.author_name,p.district,p.neighborhood,p.type,p.content,p.image_url,p.created_at,
   (select count(*) from public.post_likes l where l.post_id=p.id),
   (select count(*) from public.post_comments c where c.post_id=p.id),
   exists(select 1 from public.post_likes l where l.post_id=p.id and l.phone=v_phone)
 from public.posts p
 where v_super or p.district=v_district
 order by p.created_at desc limit 200;
end $function$
;

revoke all on function app_private.legacy_list_posts_social_for_phone(p_phone text) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.list_posts_social_for_phone(p_phone text)
 RETURNS TABLE(id uuid, author_phone text, author_name text, district text, neighborhood text, type text, content text, image_url text, created_at timestamp with time zone, like_count bigint, comment_count bigint, liked boolean)
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); return query select * from app_private.legacy_list_posts_social_for_phone(p_phone); end $guard$;
revoke all on function public.list_posts_social_for_phone(p_phone text) from public,anon;
grant execute on function public.list_posts_social_for_phone(p_phone text) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_list_posts_social_v420(p_phone text)
 RETURNS TABLE(id uuid, author_phone text, author_name text, author_avatar text, district text, neighborhood text, type text, content text, image_url text, created_at timestamp with time zone, like_count bigint, comment_count bigint, liked boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_phone text:=regexp_replace(coalesce(p_phone,''),'\D','','g'); v_district text; v_super boolean:=false;
begin
 select p.district,coalesce(p.is_super_admin,false) into v_district,v_super from public.profiles p where p.phone=v_phone limit 1;
 if v_phone='500000000' then v_super:=true; end if;
 return query
 select p.id,p.author_phone,p.author_name,pr.avatar_url,p.district,p.neighborhood,p.type,p.content,p.image_url,p.created_at,
        (select count(*) from public.post_likes l where l.post_id=p.id),
        (select count(*) from public.post_comments c where c.post_id=p.id),
        exists(select 1 from public.post_likes l where l.post_id=p.id and l.phone=v_phone)
 from public.posts p left join public.profiles pr on pr.phone=p.author_phone
 where v_super or p.district=v_district
 order by p.created_at desc limit 300;
end $function$
;

revoke all on function app_private.legacy_list_posts_social_v420(p_phone text) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.list_posts_social_v420(p_phone text)
 RETURNS TABLE(id uuid, author_phone text, author_name text, author_avatar text, district text, neighborhood text, type text, content text, image_url text, created_at timestamp with time zone, like_count bigint, comment_count bigint, liked boolean)
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); return query select * from app_private.legacy_list_posts_social_v420(p_phone); end $guard$;
revoke all on function public.list_posts_social_v420(p_phone text) from public,anon;
grant execute on function public.list_posts_social_v420(p_phone text) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_list_provider_service_orders(p_phone text)
 RETURNS TABLE(id uuid, customer_phone text, customer_name text, provider_phone text, provider_name text, category text, description text, address text, requested_time timestamp with time zone, starting_price numeric, final_price numeric, status text, cancel_reason text, dispute_reason text, funds_held boolean, commission numeric, payout numeric, created_at timestamp with time zone, updated_at timestamp with time zone, completed_at timestamp with time zone, rating integer, review_comment text)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
 select o.id,o.customer_phone,p.full_name,o.provider_phone,o.provider_name,o.category,o.description,o.address,
        o.requested_time,o.starting_price,o.final_price,o.status,o.cancel_reason,o.dispute_reason,
        o.funds_held,o.commission,o.payout,o.created_at,o.updated_at,o.completed_at,
        r.rating,r.comment
 from public.service_orders o
 join public.profiles p on p.phone=o.customer_phone
 left join public.service_order_reviews r on r.order_id=o.id
 where o.provider_phone=regexp_replace(coalesce(p_phone,''),'\D','','g')
 order by o.created_at desc limit 200;
$function$
;

revoke all on function app_private.legacy_list_provider_service_orders(p_phone text) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.list_provider_service_orders(p_phone text)
 RETURNS TABLE(id uuid, customer_phone text, customer_name text, provider_phone text, provider_name text, category text, description text, address text, requested_time timestamp with time zone, starting_price numeric, final_price numeric, status text, cancel_reason text, dispute_reason text, funds_held boolean, commission numeric, payout numeric, created_at timestamp with time zone, updated_at timestamp with time zone, completed_at timestamp with time zone, rating integer, review_comment text)
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); return query select * from app_private.legacy_list_provider_service_orders(p_phone); end $guard$;
revoke all on function public.list_provider_service_orders(p_phone text) from public,anon;
grant execute on function public.list_provider_service_orders(p_phone text) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_list_public_businesses(p_phone text)
 RETURNS TABLE(id uuid, name text, category text, description text, address text, contact_phone text, website text, hours text, image_url text, lat double precision, lng double precision, is_premium boolean, discount_title text, discount_percent numeric)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
 select b.id,b.name,b.category,b.description,b.address,b.contact_phone,b.website,b.hours,b.image_url,b.lat,b.lng,b.is_premium,d.title,d.percent
 from public.businesses b left join public.business_discounts d on d.business_id=b.id and d.active=true
 where b.status='approved' order by b.is_premium desc,b.updated_at desc limit 200;
$function$
;

revoke all on function app_private.legacy_list_public_businesses(p_phone text) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.list_public_businesses(p_phone text)
 RETURNS TABLE(id uuid, name text, category text, description text, address text, contact_phone text, website text, hours text, image_url text, lat double precision, lng double precision, is_premium boolean, discount_title text, discount_percent numeric)
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); return query select * from app_private.legacy_list_public_businesses(p_phone); end $guard$;
revoke all on function public.list_public_businesses(p_phone text) from public,anon;
grant execute on function public.list_public_businesses(p_phone text) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_list_public_profile_marketplace(p_viewer_phone text, p_profile_phone text)
 RETURNS TABLE(id uuid, owner_phone text, owner_name text, district text, neighborhood text, title text, description text, category text, price numeric, image_url text, status text, created_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_viewer text:=regexp_replace(coalesce(p_viewer_phone,''),'\D','','g');
  v_target text:=regexp_replace(coalesce(p_profile_phone,''),'\D','','g');
begin
  if not exists(select 1 from public.profiles where profiles.phone=v_viewer) then return; end if;
  return query
  select m.id,m.owner_phone,m.owner_name,m.district,m.neighborhood,m.title,m.description,m.category,m.price,m.image_url,m.status,m.created_at
  from public.marketplace_listings m
  where m.owner_phone=v_target and m.status='active'
  order by m.created_at desc
  limit 200;
end $function$
;

revoke all on function app_private.legacy_list_public_profile_marketplace(p_viewer_phone text, p_profile_phone text) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.list_public_profile_marketplace(p_viewer_phone text, p_profile_phone text)
 RETURNS TABLE(id uuid, owner_phone text, owner_name text, district text, neighborhood text, title text, description text, category text, price numeric, image_url text, status text, created_at timestamp with time zone)
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_viewer_phone); return query select * from app_private.legacy_list_public_profile_marketplace(p_viewer_phone,p_profile_phone); end $guard$;
revoke all on function public.list_public_profile_marketplace(p_viewer_phone text, p_profile_phone text) from public,anon;
grant execute on function public.list_public_profile_marketplace(p_viewer_phone text, p_profile_phone text) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_list_public_profile_posts(p_viewer_phone text, p_profile_phone text)
 RETURNS TABLE(id uuid, author_phone text, author_name text, district text, neighborhood text, type text, content text, image_url text, created_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_viewer text:=regexp_replace(coalesce(p_viewer_phone,''),'\D','','g');
  v_target text:=regexp_replace(coalesce(p_profile_phone,''),'\D','','g');
begin
  if not exists(select 1 from public.profiles where profiles.phone=v_viewer) then return; end if;
  return query
  select p.id,p.author_phone,p.author_name,p.district,p.neighborhood,p.type,p.content,p.image_url,p.created_at
  from public.posts p
  where p.author_phone=v_target
  order by p.created_at desc
  limit 200;
end $function$
;

revoke all on function app_private.legacy_list_public_profile_posts(p_viewer_phone text, p_profile_phone text) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.list_public_profile_posts(p_viewer_phone text, p_profile_phone text)
 RETURNS TABLE(id uuid, author_phone text, author_name text, district text, neighborhood text, type text, content text, image_url text, created_at timestamp with time zone)
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_viewer_phone); return query select * from app_private.legacy_list_public_profile_posts(p_viewer_phone,p_profile_phone); end $guard$;
revoke all on function public.list_public_profile_posts(p_viewer_phone text, p_profile_phone text) from public,anon;
grant execute on function public.list_public_profile_posts(p_viewer_phone text, p_profile_phone text) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_list_public_profile_specialist_ads(p_viewer_phone text, p_profile_phone text)
 RETURNS TABLE(id uuid, owner_phone text, owner_name text, contact_phone text, title text, body text, price numeric, image_url text, target_districts text[], work_hours text, status text, created_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_viewer text:=regexp_replace(coalesce(p_viewer_phone,''),'\D','','g');
  v_target text:=regexp_replace(coalesce(p_profile_phone,''),'\D','','g');
begin
  if not exists(select 1 from public.profiles where profiles.phone=v_viewer) then return; end if;
  return query
  select a.id,a.owner_phone,a.owner_name,a.contact_phone,a.title,a.body,a.price,a.image_url,a.target_districts,a.work_hours,a.status,a.created_at
  from public.specialist_announcements a
  where a.owner_phone=v_target and a.status='approved'
  order by a.created_at desc
  limit 100;
end $function$
;

revoke all on function app_private.legacy_list_public_profile_specialist_ads(p_viewer_phone text, p_profile_phone text) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.list_public_profile_specialist_ads(p_viewer_phone text, p_profile_phone text)
 RETURNS TABLE(id uuid, owner_phone text, owner_name text, contact_phone text, title text, body text, price numeric, image_url text, target_districts text[], work_hours text, status text, created_at timestamp with time zone)
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_viewer_phone); return query select * from app_private.legacy_list_public_profile_specialist_ads(p_viewer_phone,p_profile_phone); end $guard$;
revoke all on function public.list_public_profile_specialist_ads(p_viewer_phone text, p_profile_phone text) from public,anon;
grant execute on function public.list_public_profile_specialist_ads(p_viewer_phone text, p_profile_phone text) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_list_public_specialist_announcements(p_phone text)
 RETURNS TABLE(id uuid, owner_phone text, owner_name text, contact_phone text, title text, body text, price numeric, image_url text, target_districts text[], work_hours text, status text, created_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_phone text:=regexp_replace(coalesce(p_phone,''),'\D','','g');v_district text;v_super boolean:=false;
begin
 select district,coalesce(is_super_admin,false) into v_district,v_super from public.profiles where phone=v_phone limit 1;
 if v_phone='500000000' then v_super:=true; end if;
 return query
 select a.id,a.owner_phone,a.owner_name,a.contact_phone,a.title,a.body,a.price,a.image_url,a.target_districts,a.work_hours,a.status,a.created_at
 from public.specialist_announcements a
 where a.status='approved' and (v_super or v_district=any(a.target_districts))
 order by a.created_at desc limit 100;
end $function$
;

revoke all on function app_private.legacy_list_public_specialist_announcements(p_phone text) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.list_public_specialist_announcements(p_phone text)
 RETURNS TABLE(id uuid, owner_phone text, owner_name text, contact_phone text, title text, body text, price numeric, image_url text, target_districts text[], work_hours text, status text, created_at timestamp with time zone)
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); return query select * from app_private.legacy_list_public_specialist_announcements(p_phone); end $guard$;
revoke all on function public.list_public_specialist_announcements(p_phone text) from public,anon;
grant execute on function public.list_public_specialist_announcements(p_phone text) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_list_public_user_marketplace(p_target_phone text)
 RETURNS TABLE(id uuid, title text, description text, category text, price numeric, image_url text, created_at timestamp with time zone)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
 select m.id,m.title,m.description,m.category,m.price,m.image_url,m.created_at
 from public.marketplace_listings m
 where m.owner_phone=regexp_replace(coalesce(p_target_phone,''),'\D','','g') and m.status='active'
 order by m.created_at desc limit 100;
$function$
;

revoke all on function app_private.legacy_list_public_user_marketplace(p_target_phone text) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.list_public_user_marketplace(p_target_phone text)
 RETURNS TABLE(id uuid, title text, description text, category text, price numeric, image_url text, created_at timestamp with time zone)
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.verified_phone(); return query select * from app_private.legacy_list_public_user_marketplace(p_target_phone); end $guard$;
revoke all on function public.list_public_user_marketplace(p_target_phone text) from public,anon;
grant execute on function public.list_public_user_marketplace(p_target_phone text) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_list_public_user_posts(p_target_phone text)
 RETURNS TABLE(id uuid, author_phone text, author_name text, district text, neighborhood text, type text, content text, image_url text, created_at timestamp with time zone)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
 select p.id,p.author_phone,p.author_name,p.district,p.neighborhood,p.type,p.content,p.image_url,p.created_at
 from public.posts p where p.author_phone=regexp_replace(coalesce(p_target_phone,''),'\D','','g')
 order by p.created_at desc limit 100;
$function$
;

revoke all on function app_private.legacy_list_public_user_posts(p_target_phone text) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.list_public_user_posts(p_target_phone text)
 RETURNS TABLE(id uuid, author_phone text, author_name text, district text, neighborhood text, type text, content text, image_url text, created_at timestamp with time zone)
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.verified_phone(); return query select * from app_private.legacy_list_public_user_posts(p_target_phone); end $guard$;
revoke all on function public.list_public_user_posts(p_target_phone text) from public,anon;
grant execute on function public.list_public_user_posts(p_target_phone text) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_list_public_user_specialist_ads(p_target_phone text)
 RETURNS TABLE(id uuid, title text, body text, price numeric, image_url text, work_hours text, status text, created_at timestamp with time zone)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
 select a.id,a.title,a.body,a.price,a.image_url,a.work_hours,a.status,a.created_at
 from public.specialist_announcements a
 where a.owner_phone=regexp_replace(coalesce(p_target_phone,''),'\D','','g') and a.status='approved'
 order by a.created_at desc limit 100;
$function$
;

revoke all on function app_private.legacy_list_public_user_specialist_ads(p_target_phone text) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.list_public_user_specialist_ads(p_target_phone text)
 RETURNS TABLE(id uuid, title text, body text, price numeric, image_url text, work_hours text, status text, created_at timestamp with time zone)
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.verified_phone(); return query select * from app_private.legacy_list_public_user_specialist_ads(p_target_phone); end $guard$;
revoke all on function public.list_public_user_specialist_ads(p_target_phone text) from public,anon;
grant execute on function public.list_public_user_specialist_ads(p_target_phone text) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_list_service_orders_admin(p_phone text)
 RETURNS TABLE(id uuid, customer_phone text, customer_name text, provider_phone text, provider_name text, category text, description text, address text, final_price numeric, status text, dispute_reason text, funds_held boolean, commission numeric, payout numeric, created_at timestamp with time zone, completed_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_phone text:=regexp_replace(coalesce(p_phone,''),'\D','','g');v_super boolean:=false;
begin
 select coalesce(is_super_admin,false) into v_super from public.profiles where phone=v_phone;
 if v_phone='500000000' then v_super:=true; end if;
 if not v_super then return; end if;
 return query
 select o.id,o.customer_phone,p.full_name,o.provider_phone,o.provider_name,o.category,o.description,o.address,
        o.final_price,o.status,o.dispute_reason,o.funds_held,o.commission,o.payout,o.created_at,o.completed_at
 from public.service_orders o join public.profiles p on p.phone=o.customer_phone
 order by o.created_at desc limit 500;
end $function$
;

revoke all on function app_private.legacy_list_service_orders_admin(p_phone text) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.list_service_orders_admin(p_phone text)
 RETURNS TABLE(id uuid, customer_phone text, customer_name text, provider_phone text, provider_name text, category text, description text, address text, final_price numeric, status text, dispute_reason text, funds_held boolean, commission numeric, payout numeric, created_at timestamp with time zone, completed_at timestamp with time zone)
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); perform app_private.require_admin(); return query select * from app_private.legacy_list_service_orders_admin(p_phone); end $guard$;
revoke all on function public.list_service_orders_admin(p_phone text) from public,anon;
grant execute on function public.list_service_orders_admin(p_phone text) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_list_specialist_announcements_admin(p_phone text)
 RETURNS TABLE(id uuid, owner_phone text, owner_name text, contact_phone text, title text, body text, price numeric, image_url text, target_districts text[], work_hours text, status text, review_note text, created_at timestamp with time zone, reviewed_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_phone text:=regexp_replace(coalesce(p_phone,''),'\D','','g');v_super boolean:=false;
begin
 select coalesce(is_super_admin,false) into v_super from public.profiles where phone=v_phone;
 if v_phone='500000000' then v_super:=true; end if;
 if not v_super then return; end if;
 return query select a.id,a.owner_phone,a.owner_name,a.contact_phone,a.title,a.body,a.price,a.image_url,a.target_districts,a.work_hours,a.status,a.review_note,a.created_at,a.reviewed_at
 from public.specialist_announcements a order by a.created_at desc;
end $function$
;

revoke all on function app_private.legacy_list_specialist_announcements_admin(p_phone text) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.list_specialist_announcements_admin(p_phone text)
 RETURNS TABLE(id uuid, owner_phone text, owner_name text, contact_phone text, title text, body text, price numeric, image_url text, target_districts text[], work_hours text, status text, review_note text, created_at timestamp with time zone, reviewed_at timestamp with time zone)
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); perform app_private.require_admin(); return query select * from app_private.legacy_list_specialist_announcements_admin(p_phone); end $guard$;
revoke all on function public.list_specialist_announcements_admin(p_phone text) from public,anon;
grant execute on function public.list_specialist_announcements_admin(p_phone text) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_mark_direct_chat_read(p_phone text, p_thread_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_phone text:=regexp_replace(coalesce(p_phone,''),'\D','','g');
begin
  if not exists(select 1 from public.direct_chat_threads where id=p_thread_id and v_phone in(user_a,user_b)) then return jsonb_build_object('ok',false);end if;
  insert into public.direct_chat_reads(thread_id,phone,last_read_at) values(p_thread_id,v_phone,now())
    on conflict(thread_id,phone) do update set last_read_at=excluded.last_read_at;
  return jsonb_build_object('ok',true);
end;
$function$
;

revoke all on function app_private.legacy_mark_direct_chat_read(p_phone text, p_thread_id uuid) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.mark_direct_chat_read(p_phone text, p_thread_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); return app_private.legacy_mark_direct_chat_read(p_phone,p_thread_id); end $guard$;
revoke all on function public.mark_direct_chat_read(p_phone text, p_thread_id uuid) from public,anon;
grant execute on function public.mark_direct_chat_read(p_phone text, p_thread_id uuid) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_mark_live_chat_read(p_phone text, p_chat_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_phone text:=regexp_replace(coalesce(p_phone,''),'\D','','g');
begin
  update public.live_chat_members set last_read_at=now() where chat_id=p_chat_id and phone=v_phone;
  return jsonb_build_object('ok',found);
end;
$function$
;

revoke all on function app_private.legacy_mark_live_chat_read(p_phone text, p_chat_id uuid) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.mark_live_chat_read(p_phone text, p_chat_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); return app_private.legacy_mark_live_chat_read(p_phone,p_chat_id); end $guard$;
revoke all on function public.mark_live_chat_read(p_phone text, p_chat_id uuid) from public,anon;
grant execute on function public.mark_live_chat_read(p_phone text, p_chat_id uuid) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_mark_notification_read(p_phone text, p_notification_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
 update public.notifications set is_read=true where id=p_notification_id and recipient_phone=regexp_replace(coalesce(p_phone,''),'\D','','g');
 return jsonb_build_object('ok',true);
end $function$
;

revoke all on function app_private.legacy_mark_notification_read(p_phone text, p_notification_id uuid) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.mark_notification_read(p_phone text, p_notification_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); return app_private.legacy_mark_notification_read(p_phone,p_notification_id); end $guard$;
revoke all on function public.mark_notification_read(p_phone text, p_notification_id uuid) from public,anon;
grant execute on function public.mark_notification_read(p_phone text, p_notification_id uuid) to authenticated;

revoke all on function public.my_day_are_friends(p_a text, p_b text) from public,anon,authenticated;

revoke all on function public.phone_exists(p_phone text) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_provider_service_order_action(p_phone text, p_id uuid, p_action text, p_amount numeric DEFAULT NULL::numeric, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
 v_phone text:=regexp_replace(coalesce(p_phone,''),'\D','','g');
 v public.service_orders%rowtype;
begin
 select * into v from public.service_orders where id=p_id and provider_phone=v_phone for update;
 if not found then return jsonb_build_object('ok',false,'message','შეკვეთა ვერ მოიძებნა ან უფლება არ გაქვს'); end if;

 if p_action='accept' and v.status='consultation_requested' then
   update public.service_orders set status='accepted',updated_at=now() where id=p_id;
 elsif p_action='reject' and v.status in ('consultation_requested','accepted') then
   update public.service_orders set status='cancelled',cancel_reason=nullif(trim(coalesce(p_reason,'')),''),updated_at=now() where id=p_id;
 elsif p_action='offer' and v.status='accepted' then
   if coalesce(p_amount,0)<=0 then return jsonb_build_object('ok',false,'message','ფასი მიუთითე'); end if;
   update public.service_orders set final_price=p_amount,status='offer_sent',updated_at=now() where id=p_id;
 elsif p_action='done' and v.status='funds_held' and v.funds_held then
   update public.service_orders set status='work_done_pending',updated_at=now() where id=p_id;
 else
   return jsonb_build_object('ok',false,'message','ამ ეტაპზე ეს მოქმედება შეუძლებელია');
 end if;
 return jsonb_build_object('ok',true);
end $function$
;

revoke all on function app_private.legacy_provider_service_order_action(p_phone text, p_id uuid, p_action text, p_amount numeric, p_reason text) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.provider_service_order_action(p_phone text, p_id uuid, p_action text, p_amount numeric DEFAULT NULL::numeric, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); return app_private.legacy_provider_service_order_action(p_phone,p_id,p_action,p_amount,p_reason); end $guard$;
revoke all on function public.provider_service_order_action(p_phone text, p_id uuid, p_action text, p_amount numeric, p_reason text) from public,anon;
grant execute on function public.provider_service_order_action(p_phone text, p_id uuid, p_action text, p_amount numeric, p_reason text) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_rate_service_order(p_phone text, p_id uuid, p_rating integer, p_comment text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
 v_phone text:=regexp_replace(coalesce(p_phone,''),'\D','','g');v_provider text;
begin
 if p_rating<1 or p_rating>5 then return jsonb_build_object('ok',false,'message','შეფასება უნდა იყოს 1-5'); end if;
 select provider_phone into v_provider from public.service_orders where id=p_id and customer_phone=v_phone and status='done';
 if v_provider is null then return jsonb_build_object('ok',false,'message','დასრულებული შეკვეთა ვერ მოიძებნა'); end if;
 insert into public.service_order_reviews(order_id,customer_phone,provider_phone,rating,comment)
 values(p_id,v_phone,v_provider,p_rating,nullif(trim(coalesce(p_comment,'')),''))
 on conflict(order_id) do update set rating=excluded.rating,comment=excluded.comment,created_at=now();
 return jsonb_build_object('ok',true);
end $function$
;

revoke all on function app_private.legacy_rate_service_order(p_phone text, p_id uuid, p_rating integer, p_comment text) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.rate_service_order(p_phone text, p_id uuid, p_rating integer, p_comment text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); return app_private.legacy_rate_service_order(p_phone,p_id,p_rating,p_comment); end $guard$;
revoke all on function public.rate_service_order(p_phone text, p_id uuid, p_rating integer, p_comment text) from public,anon;
grant execute on function public.rate_service_order(p_phone text, p_id uuid, p_rating integer, p_comment text) to authenticated;

revoke all on function public.register_profile(p_phone text, p_full_name text, p_district text, p_neighborhood text) from public,anon,authenticated;

revoke all on function public.register_verified_profile(p_full_name text, p_city text, p_district text, p_neighborhood text, p_account_types text[], p_other_service text, p_specialist_profile jsonb) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_remove_daily_friend(p_phone text, p_friend_phone text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare a text:=public.norm_daily_phone(p_phone); b text:=public.norm_daily_phone(p_friend_phone);
begin delete from daily_photo_friends where (user_phone=a and friend_phone=b) or (user_phone=b and friend_phone=a); return jsonb_build_object('ok',true); end$function$
;

revoke all on function app_private.legacy_remove_daily_friend(p_phone text, p_friend_phone text) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.remove_daily_friend(p_phone text, p_friend_phone text)
 RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); return app_private.legacy_remove_daily_friend(p_phone,p_friend_phone); end $guard$;
revoke all on function public.remove_daily_friend(p_phone text, p_friend_phone text) from public,anon;
grant execute on function public.remove_daily_friend(p_phone text, p_friend_phone text) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_remove_live_chat_member(p_phone text, p_chat_id uuid, p_member_phone text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_phone text:=regexp_replace(coalesce(p_phone,''),'\D','','g');v_member text:=regexp_replace(coalesce(p_member_phone,''),'\D','','g');v_myrole text;v_targetrole text;
begin
 select role into v_myrole from public.live_chat_members where chat_id=p_chat_id and phone=v_phone;
 select role into v_targetrole from public.live_chat_members where chat_id=p_chat_id and phone=v_member;
 if v_targetrole='owner' then return jsonb_build_object('ok',false,'message','Owner-ის ამოშლა არ შეიძლება'); end if;
 if v_myrole='owner' or (v_myrole='admin' and v_targetrole='member') then delete from public.live_chat_members where chat_id=p_chat_id and phone=v_member;return jsonb_build_object('ok',true);end if;
 return jsonb_build_object('ok',false,'message','ამოშლის უფლება არ გაქვს');
end $function$
;

revoke all on function app_private.legacy_remove_live_chat_member(p_phone text, p_chat_id uuid, p_member_phone text) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.remove_live_chat_member(p_phone text, p_chat_id uuid, p_member_phone text)
 RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); return app_private.legacy_remove_live_chat_member(p_phone,p_chat_id,p_member_phone); end $guard$;
revoke all on function public.remove_live_chat_member(p_phone text, p_chat_id uuid, p_member_phone text) from public,anon;
grant execute on function public.remove_live_chat_member(p_phone text, p_chat_id uuid, p_member_phone text) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_remove_my_day_friend(p_phone text, p_friend_phone text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_me text:=regexp_replace(coalesce(p_phone,''),'\D','','g');v_friend text:=regexp_replace(coalesce(p_friend_phone,''),'\D','','g');
begin
 delete from public.my_day_friendships where (requester_phone=v_me and addressee_phone=v_friend) or (requester_phone=v_friend and addressee_phone=v_me);
 return jsonb_build_object('ok',true);
end $function$
;

revoke all on function app_private.legacy_remove_my_day_friend(p_phone text, p_friend_phone text) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.remove_my_day_friend(p_phone text, p_friend_phone text)
 RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); return app_private.legacy_remove_my_day_friend(p_phone,p_friend_phone); end $guard$;
revoke all on function public.remove_my_day_friend(p_phone text, p_friend_phone text) from public,anon;
grant execute on function public.remove_my_day_friend(p_phone text, p_friend_phone text) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_report_user(p_phone text, p_other_phone text, p_category text, p_details text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_phone text:=regexp_replace(coalesce(p_phone,''),'\D','','g');v_other text:=regexp_replace(coalesce(p_other_phone,''),'\D','','g');v_category text:=lower(trim(coalesce(p_category,'')));v_id uuid;
begin
  if v_phone='' or v_other='' or v_phone=v_other or not exists(select 1 from public.profiles where phone=v_other) then return jsonb_build_object('ok',false,'message','მომხმარებელი ვერ მოიძებნა');end if;
  if v_category not in('spam','harassment','fraud','inappropriate','other') then return jsonb_build_object('ok',false,'message','აირჩიე საჩივრის მიზეზი');end if;
  insert into public.user_reports(reporter_phone,reported_phone,category,details) values(v_phone,v_other,v_category,nullif(trim(coalesce(p_details,'')),'')) returning id into v_id;
  return jsonb_build_object('ok',true,'id',v_id);
end;
$function$
;

revoke all on function app_private.legacy_report_user(p_phone text, p_other_phone text, p_category text, p_details text) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.report_user(p_phone text, p_other_phone text, p_category text, p_details text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); return app_private.legacy_report_user(p_phone,p_other_phone,p_category,p_details); end $guard$;
revoke all on function public.report_user(p_phone text, p_other_phone text, p_category text, p_details text) from public,anon;
grant execute on function public.report_user(p_phone text, p_other_phone text, p_category text, p_details text) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_request_business_premium(p_phone text, p_business_id uuid, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_phone text:=regexp_replace(coalesce(p_phone,''),'\D','','g');
begin
 if not exists(select 1 from public.businesses where id=p_business_id and owner_phone=v_phone and status='approved') then return jsonb_build_object('ok',false,'message','Premium მოთხოვნა მხოლოდ დამტკიცებულ ბიზნესზეა შესაძლებელი'); end if;
 insert into public.business_premium_requests(business_id,owner_phone,note,status,created_at,reviewed_at) values(p_business_id,v_phone,nullif(trim(coalesce(p_note,'')),''),'pending',now(),null) on conflict(business_id) do update set note=excluded.note,status='pending',created_at=now(),reviewed_at=null;
 return jsonb_build_object('ok',true);
end $function$
;

revoke all on function app_private.legacy_request_business_premium(p_phone text, p_business_id uuid, p_note text) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.request_business_premium(p_phone text, p_business_id uuid, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); return app_private.legacy_request_business_premium(p_phone,p_business_id,p_note); end $guard$;
revoke all on function public.request_business_premium(p_phone text, p_business_id uuid, p_note text) from public,anon;
grant execute on function public.request_business_premium(p_phone text, p_business_id uuid, p_note text) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_resolve_service_order_dispute(p_phone text, p_id uuid, p_decision text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_phone text:=regexp_replace(coalesce(p_phone,''),'\D','','g');v_super boolean:=false;v public.service_orders%rowtype;
begin
 select coalesce(is_super_admin,false) into v_super from public.profiles where phone=v_phone;
 if v_phone='500000000' then v_super:=true; end if;
 if not v_super then return jsonb_build_object('ok',false,'message','Super Admin უფლება საჭიროა'); end if;
 select * into v from public.service_orders where id=p_id and status='disputed' for update;
 if not found then return jsonb_build_object('ok',false,'message','ღია დავა ვერ მოიძებნა'); end if;
 if p_decision='refund' then
   update public.service_orders set status='refunded',funds_held=false,commission=0,payout=0,updated_at=now() where id=p_id;
 elsif p_decision='release' then
   update public.service_orders set status='done',funds_held=false,commission=round((final_price*0.10)::numeric,2),payout=round((final_price*0.90)::numeric,2),completed_at=now(),updated_at=now() where id=p_id;
 else return jsonb_build_object('ok',false,'message','უცნობი გადაწყვეტილება');
 end if;
 return jsonb_build_object('ok',true);
end $function$
;

revoke all on function app_private.legacy_resolve_service_order_dispute(p_phone text, p_id uuid, p_decision text) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.resolve_service_order_dispute(p_phone text, p_id uuid, p_decision text)
 RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); perform app_private.require_admin(); return app_private.legacy_resolve_service_order_dispute(p_phone,p_id,p_decision); end $guard$;
revoke all on function public.resolve_service_order_dispute(p_phone text, p_id uuid, p_decision text) from public,anon;
grant execute on function public.resolve_service_order_dispute(p_phone text, p_id uuid, p_decision text) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_respond_my_day_friend_request(p_phone text, p_requester_phone text, p_accept boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_me text:=regexp_replace(coalesce(p_phone,''),'\D','','g');v_req text:=regexp_replace(coalesce(p_requester_phone,''),'\D','','g');
begin
  update public.my_day_friendships set status=case when p_accept then 'accepted' else 'rejected' end,updated_at=now()
  where addressee_phone=v_me and requester_phone=v_req and status='pending';
  if not found then return jsonb_build_object('ok',false,'message','მოთხოვნა ვერ მოიძებნა'); end if;
  return jsonb_build_object('ok',true,'status',case when p_accept then 'accepted' else 'rejected' end);
end $function$
;

revoke all on function app_private.legacy_respond_my_day_friend_request(p_phone text, p_requester_phone text, p_accept boolean) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.respond_my_day_friend_request(p_phone text, p_requester_phone text, p_accept boolean)
 RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); return app_private.legacy_respond_my_day_friend_request(p_phone,p_requester_phone,p_accept); end $guard$;
revoke all on function public.respond_my_day_friend_request(p_phone text, p_requester_phone text, p_accept boolean) from public,anon;
grant execute on function public.respond_my_day_friend_request(p_phone text, p_requester_phone text, p_accept boolean) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_review_business_application(p_phone text, p_id uuid, p_action text, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_status text;
begin
 if not public.can_manage_business_ads(p_phone) then return jsonb_build_object('ok',false,'message','ადმინისტრატორის უფლება საჭიროა'); end if;
 v_status:=case p_action when 'approve' then 'approved' when 'reject' then 'rejected' else null end;
 if v_status is null then return jsonb_build_object('ok',false,'message','უცნობი მოქმედება'); end if;
 update public.businesses set status=v_status,review_note=case when v_status='rejected' then nullif(trim(coalesce(p_reason,'')),'') else null end,updated_at=now() where id=p_id;
 if not found then return jsonb_build_object('ok',false,'message','ბიზნესი ვერ მოიძებნა'); end if;
 return jsonb_build_object('ok',true,'status',v_status);
end $function$
;

revoke all on function app_private.legacy_review_business_application(p_phone text, p_id uuid, p_action text, p_reason text) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.review_business_application(p_phone text, p_id uuid, p_action text, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); perform app_private.require_admin(); return app_private.legacy_review_business_application(p_phone,p_id,p_action,p_reason); end $guard$;
revoke all on function public.review_business_application(p_phone text, p_id uuid, p_action text, p_reason text) from public,anon;
grant execute on function public.review_business_application(p_phone text, p_id uuid, p_action text, p_reason text) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_review_business_premium(p_phone text, p_business_id uuid, p_approve boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_phone text:=regexp_replace(coalesce(p_phone,''),'\D','','g');v_super boolean:=false;
begin
 select coalesce(is_super_admin,false) into v_super from public.profiles where phone=v_phone; if v_phone='500000000' then v_super:=true; end if; if not v_super then return jsonb_build_object('ok',false,'message','Super Admin უფლება საჭიროა'); end if;
 update public.business_premium_requests set status=case when p_approve then 'approved' else 'rejected' end,reviewed_at=now() where business_id=p_business_id; if not found then return jsonb_build_object('ok',false,'message','Premium მოთხოვნა ვერ მოიძებნა'); end if;
 update public.businesses set is_premium=p_approve,updated_at=now() where id=p_business_id;
 return jsonb_build_object('ok',true);
end $function$
;

revoke all on function app_private.legacy_review_business_premium(p_phone text, p_business_id uuid, p_approve boolean) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.review_business_premium(p_phone text, p_business_id uuid, p_approve boolean)
 RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); perform app_private.require_admin(); return app_private.legacy_review_business_premium(p_phone,p_business_id,p_approve); end $guard$;
revoke all on function public.review_business_premium(p_phone text, p_business_id uuid, p_approve boolean) from public,anon;
grant execute on function public.review_business_premium(p_phone text, p_business_id uuid, p_approve boolean) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_review_specialist_announcement(p_phone text, p_id uuid, p_action text, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_phone text:=regexp_replace(coalesce(p_phone,''),'\D','','g');v_super boolean:=false;v_owner text;v_status text;
begin
 select coalesce(is_super_admin,false) into v_super from public.profiles where phone=v_phone;
 if v_phone='500000000' then v_super:=true; end if;
 if not v_super then return jsonb_build_object('ok',false,'message','Super Admin უფლება საჭიროა'); end if;
 v_status:=case p_action when 'approve' then 'approved' when 'reject' then 'rejected' when 'reset' then 'pending' else null end;
 if v_status is null then return jsonb_build_object('ok',false,'message','უცნობი მოქმედება'); end if;
 update public.specialist_announcements
 set status=v_status,review_note=case when v_status='rejected' then nullif(trim(coalesce(p_reason,'')),'') else null end,
     reviewed_at=case when v_status='pending' then null else now() end,reviewed_by=case when v_status='pending' then null else v_phone end
 where id=p_id returning owner_phone into v_owner;
 if v_owner is null then return jsonb_build_object('ok',false,'message','განცხადება ვერ მოიძებნა'); end if;
 return jsonb_build_object('ok',true,'status',v_status);
end $function$
;

revoke all on function app_private.legacy_review_specialist_announcement(p_phone text, p_id uuid, p_action text, p_reason text) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.review_specialist_announcement(p_phone text, p_id uuid, p_action text, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); perform app_private.require_admin(); return app_private.legacy_review_specialist_announcement(p_phone,p_id,p_action,p_reason); end $guard$;
revoke all on function public.review_specialist_announcement(p_phone text, p_id uuid, p_action text, p_reason text) from public,anon;
grant execute on function public.review_specialist_announcement(p_phone text, p_id uuid, p_action text, p_reason text) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_search_my_day_people(p_phone text, p_query text)
 RETURNS TABLE(phone text, full_name text, district text, avatar_url text, friend_status text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_me text:=regexp_replace(coalesce(p_phone,''),'\D','','g');
  v_q text:=public.my_day_phone_key(p_query);
begin
  if length(v_q)<7 then return; end if;
  return query
  select p.phone,p.full_name,p.district,p.avatar_url,
    coalesce((select f.status from public.my_day_friendships f
      where ((f.requester_phone=v_me and f.addressee_phone=p.phone) or (f.requester_phone=p.phone and f.addressee_phone=v_me))
      order by f.updated_at desc limit 1),'none')::text
  from public.profiles p
  where p.phone<>v_me and (
      public.my_day_phone_key(p.phone)=v_q
      or (length(p.phone)=9 and '995'||public.my_day_phone_key(p.phone)=v_q)
      or (v_q like '995%' and public.my_day_phone_key(p.phone)=substr(v_q,4))
  )
  limit 5;
end $function$
;

revoke all on function app_private.legacy_search_my_day_people(p_phone text, p_query text) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.search_my_day_people(p_phone text, p_query text)
 RETURNS TABLE(phone text, full_name text, district text, avatar_url text, friend_status text)
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); return query select * from app_private.legacy_search_my_day_people(p_phone,p_query); end $guard$;
revoke all on function public.search_my_day_people(p_phone text, p_query text) from public,anon;
grant execute on function public.search_my_day_people(p_phone text, p_query text) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_send_direct_message(p_phone text, p_target_phone text, p_body text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_phone text:=regexp_replace(coalesce(p_phone,''),'\D','','g'); v_target text:=regexp_replace(coalesce(p_target_phone,''),'\D','','g'); v_id uuid; v_name text;
begin
 if length(trim(coalesce(p_body,'')))=0 then return jsonb_build_object('ok',false,'message','შეტყობინება ცარიელია'); end if;
 if v_phone=v_target then return jsonb_build_object('ok',false,'message','საკუთარ თავს ვერ მისწერ'); end if;
 if not exists(select 1 from public.profiles where phone=v_phone) or not exists(select 1 from public.profiles where phone=v_target) then return jsonb_build_object('ok',false,'message','მომხმარებელი ვერ მოიძებნა'); end if;
 insert into public.direct_messages(sender_phone,recipient_phone,body) values(v_phone,v_target,trim(p_body)) returning id into v_id;
 select full_name into v_name from public.profiles where phone=v_phone;
 insert into public.notifications(recipient_phone,actor_phone,kind,title,body)
 values(v_target,v_phone,'direct_message','💬 ახალი პირადი შეტყობინება',coalesce(v_name,'მომხმარებელი')||': '||left(trim(p_body),80));
 return jsonb_build_object('ok',true,'id',v_id);
end $function$
;

revoke all on function app_private.legacy_send_direct_message(p_phone text, p_target_phone text, p_body text) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.send_direct_message(p_phone text, p_target_phone text, p_body text)
 RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); return app_private.legacy_send_direct_message(p_phone,p_target_phone,p_body); end $guard$;
revoke all on function public.send_direct_message(p_phone text, p_target_phone text, p_body text) from public,anon;
grant execute on function public.send_direct_message(p_phone text, p_target_phone text, p_body text) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_send_direct_message(p_phone text, p_thread_id uuid, p_body text DEFAULT NULL::text, p_image_url text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_phone text:=regexp_replace(coalesce(p_phone,''),'\D','','g');v_other text;v_id uuid;
begin
  select case when user_a=v_phone then user_b else user_a end into v_other from public.direct_chat_threads
    where id=p_thread_id and v_phone in(user_a,user_b);
  if v_other is null then return jsonb_build_object('ok',false,'message','დიალოგი ვერ მოიძებნა');end if;
  if public.is_user_blocked(v_phone,v_other) then return jsonb_build_object('ok',false,'message','ამ მომხმარებელთან მიმოწერა დაბლოკილია');end if;
  if length(trim(coalesce(p_body,'')))=0 and length(trim(coalesce(p_image_url,'')))=0 then return jsonb_build_object('ok',false,'message','შეტყობინება ცარიელია');end if;
  insert into public.direct_chat_messages(thread_id,sender_phone,body,image_url)
    values(p_thread_id,v_phone,nullif(trim(coalesce(p_body,'')),''),nullif(trim(coalesce(p_image_url,'')),'')) returning id into v_id;
  update public.direct_chat_threads set updated_at=now() where id=p_thread_id;
  perform public.mark_direct_chat_read(v_phone,p_thread_id);
  return jsonb_build_object('ok',true,'id',v_id);
end;
$function$
;

revoke all on function app_private.legacy_send_direct_message(p_phone text, p_thread_id uuid, p_body text, p_image_url text) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.send_direct_message(p_phone text, p_thread_id uuid, p_body text DEFAULT NULL::text, p_image_url text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); return app_private.legacy_send_direct_message(p_phone,p_thread_id,p_body,p_image_url); end $guard$;
revoke all on function public.send_direct_message(p_phone text, p_thread_id uuid, p_body text, p_image_url text) from public,anon;
grant execute on function public.send_direct_message(p_phone text, p_thread_id uuid, p_body text, p_image_url text) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_send_live_chat_message(p_phone text, p_chat_id uuid, p_body text DEFAULT NULL::text, p_image_url text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_phone text:=regexp_replace(coalesce(p_phone,''),'\D','','g');
  v_name text;
  v_id uuid;
begin
  if not exists(select 1 from public.live_chat_members where chat_id=p_chat_id and phone=v_phone) then
    return jsonb_build_object('ok',false,'message','ამ ჩათის წევრი არ ხარ');
  end if;
  if length(trim(coalesce(p_body,'')))=0 and nullif(trim(coalesce(p_image_url,'')),'') is null then
    return jsonb_build_object('ok',false,'message','შეტყობინება ცარიელია');
  end if;
  select full_name into v_name from public.profiles where phone=v_phone;
  insert into public.live_chat_messages(chat_id,sender_phone,sender_name,body,image_url)
  values(p_chat_id,v_phone,v_name,nullif(trim(coalesce(p_body,'')),''),nullif(trim(coalesce(p_image_url,'')),'')) returning id into v_id;
  return jsonb_build_object('ok',true,'id',v_id);
end $function$
;

revoke all on function app_private.legacy_send_live_chat_message(p_phone text, p_chat_id uuid, p_body text, p_image_url text) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.send_live_chat_message(p_phone text, p_chat_id uuid, p_body text DEFAULT NULL::text, p_image_url text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); return app_private.legacy_send_live_chat_message(p_phone,p_chat_id,p_body,p_image_url); end $guard$;
revoke all on function public.send_live_chat_message(p_phone text, p_chat_id uuid, p_body text, p_image_url text) from public,anon;
grant execute on function public.send_live_chat_message(p_phone text, p_chat_id uuid, p_body text, p_image_url text) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_send_my_day_friend_request(p_phone text, p_target_phone text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_me text:=regexp_replace(coalesce(p_phone,''),'\D','','g');
  v_target text:=regexp_replace(coalesce(p_target_phone,''),'\D','','g');
  v_existing public.my_day_friendships%rowtype;
begin
  if v_me=v_target then return jsonb_build_object('ok',false,'message','საკუთარ თავს ვერ დაამატებ'); end if;
  if not exists(select 1 from public.profiles where phone=v_me) then return jsonb_build_object('ok',false,'message','პროფილი ვერ მოიძებნა'); end if;
  if not exists(select 1 from public.profiles where phone=v_target) then return jsonb_build_object('ok',false,'message','მომხმარებელი ვერ მოიძებნა'); end if;
  select * into v_existing from public.my_day_friendships f
  where (f.requester_phone=v_me and f.addressee_phone=v_target) or (f.requester_phone=v_target and f.addressee_phone=v_me)
  order by f.updated_at desc limit 1;
  if found then
    if v_existing.status='accepted' then return jsonb_build_object('ok',true,'status','accepted'); end if;
    if v_existing.status='pending' then return jsonb_build_object('ok',true,'status','pending'); end if;
    update public.my_day_friendships set requester_phone=v_me,addressee_phone=v_target,status='pending',updated_at=now() where id=v_existing.id;
  else
    insert into public.my_day_friendships(requester_phone,addressee_phone,status) values(v_me,v_target,'pending');
  end if;
  if to_regclass('public.notifications') is not null then
    insert into public.notifications(recipient_phone,actor_phone,kind,title,body)
    values(v_target,v_me,'my_day_friend_request','📸 ახალი მეგობრობის მოთხოვნა','„ჩემი დღე“-ში მეგობრობა გამოგიგზავნეს');
  end if;
  return jsonb_build_object('ok',true,'status','pending');
end $function$
;

revoke all on function app_private.legacy_send_my_day_friend_request(p_phone text, p_target_phone text) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.send_my_day_friend_request(p_phone text, p_target_phone text)
 RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); return app_private.legacy_send_my_day_friend_request(p_phone,p_target_phone); end $guard$;
revoke all on function public.send_my_day_friend_request(p_phone text, p_target_phone text) from public,anon;
grant execute on function public.send_my_day_friend_request(p_phone text, p_target_phone text) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_set_business_discount(p_phone text, p_business_id uuid, p_title text, p_percent numeric DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_phone text:=regexp_replace(coalesce(p_phone,''),'\D','','g');
begin
 if not exists(select 1 from public.businesses where id=p_business_id and owner_phone=v_phone and status='approved') then return jsonb_build_object('ok',false,'message','მხოლოდ დამტკიცებულ საკუთარ ბიზნესზე შეგიძლია ფასდაკლების დამატება'); end if;
 insert into public.business_discounts(business_id,title,percent,active,updated_at) values(p_business_id,trim(p_title),greatest(0,least(coalesce(p_percent,0),100)),true,now()) on conflict(business_id) do update set title=excluded.title,percent=excluded.percent,active=true,updated_at=now();
 return jsonb_build_object('ok',true);
end $function$
;

revoke all on function app_private.legacy_set_business_discount(p_phone text, p_business_id uuid, p_title text, p_percent numeric) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.set_business_discount(p_phone text, p_business_id uuid, p_title text, p_percent numeric DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); perform app_private.require_admin(); return app_private.legacy_set_business_discount(p_phone,p_business_id,p_title,p_percent); end $guard$;
revoke all on function public.set_business_discount(p_phone text, p_business_id uuid, p_title text, p_percent numeric) from public,anon;
grant execute on function public.set_business_discount(p_phone text, p_business_id uuid, p_title text, p_percent numeric) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_set_live_chat_member_role(p_phone text, p_chat_id uuid, p_member_phone text, p_role text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_phone text:=regexp_replace(coalesce(p_phone,''),'\D','','g');v_member text:=regexp_replace(coalesce(p_member_phone,''),'\D','','g');
begin
 if p_role not in ('admin','member') then return jsonb_build_object('ok',false,'message','არასწორი როლი'); end if;
 if not exists(select 1 from public.live_chat_members where chat_id=p_chat_id and phone=v_phone and role='owner') then return jsonb_build_object('ok',false,'message','მხოლოდ Owner-ს შეუძლია როლის შეცვლა'); end if;
 update public.live_chat_members set role=p_role where chat_id=p_chat_id and phone=v_member and role<>'owner';
 if not found then return jsonb_build_object('ok',false,'message','წევრი ვერ მოიძებნა'); end if;
 return jsonb_build_object('ok',true);
end $function$
;

revoke all on function app_private.legacy_set_live_chat_member_role(p_phone text, p_chat_id uuid, p_member_phone text, p_role text) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.set_live_chat_member_role(p_phone text, p_chat_id uuid, p_member_phone text, p_role text)
 RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); return app_private.legacy_set_live_chat_member_role(p_phone,p_chat_id,p_member_phone,p_role); end $guard$;
revoke all on function public.set_live_chat_member_role(p_phone text, p_chat_id uuid, p_member_phone text, p_role text) from public,anon;
grant execute on function public.set_live_chat_member_role(p_phone text, p_chat_id uuid, p_member_phone text, p_role text) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_start_direct_chat(p_phone text, p_other_phone text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_phone text:=regexp_replace(coalesce(p_phone,''),'\D','','g');
  v_other text:=regexp_replace(coalesce(p_other_phone,''),'\D','','g');
  v_a text;v_b text;v_id uuid;
begin
  if v_phone='' or v_other='' or v_phone=v_other then return jsonb_build_object('ok',false,'message','მომხმარებელი არასწორადაა არჩეული');end if;
  if not exists(select 1 from public.profiles where phone=v_phone) or not exists(select 1 from public.profiles where phone=v_other) then
    return jsonb_build_object('ok',false,'message','პროფილი ვერ მოიძებნა');
  end if;
  if public.is_user_blocked(v_phone,v_other) then return jsonb_build_object('ok',false,'message','ამ მომხმარებელთან მიმოწერა დაბლოკილია');end if;
  v_a:=least(v_phone,v_other);v_b:=greatest(v_phone,v_other);
  insert into public.direct_chat_threads(user_a,user_b) values(v_a,v_b)
    on conflict(user_a,user_b) do update set updated_at=public.direct_chat_threads.updated_at returning id into v_id;
  insert into public.direct_chat_reads(thread_id,phone,last_read_at) values(v_id,v_phone,now())
    on conflict(thread_id,phone) do nothing;
  insert into public.direct_chat_reads(thread_id,phone,last_read_at) values(v_id,v_other,now())
    on conflict(thread_id,phone) do nothing;
  return jsonb_build_object('ok',true,'id',v_id);
end;
$function$
;

revoke all on function app_private.legacy_start_direct_chat(p_phone text, p_other_phone text) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.start_direct_chat(p_phone text, p_other_phone text)
 RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); return app_private.legacy_start_direct_chat(p_phone,p_other_phone); end $guard$;
revoke all on function public.start_direct_chat(p_phone text, p_other_phone text) from public,anon;
grant execute on function public.start_direct_chat(p_phone text, p_other_phone text) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_submit_business_application(p_phone text, p_name text, p_category text, p_description text, p_address text, p_contact_phone text DEFAULT NULL::text, p_website text DEFAULT NULL::text, p_hours text DEFAULT NULL::text, p_image_url text DEFAULT NULL::text, p_lat double precision DEFAULT NULL::double precision, p_lng double precision DEFAULT NULL::double precision)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_phone text:=regexp_replace(coalesce(p_phone,''),'\\D','','g');
  v_id uuid;
  v_owner text;
begin
  select full_name into v_owner from public.profiles where phone=v_phone;
  if v_owner is null then
    return jsonb_build_object('ok',false,'message','პროფილი ვერ მოიძებნა');
  end if;

  if length(trim(coalesce(p_name,'')))<2 or length(trim(coalesce(p_address,'')))<2 then
    return jsonb_build_object('ok',false,'message','შეავსე ბიზნესის სახელი და მისამართი');
  end if;
  if length(trim(coalesce(p_category,'')))<2 then
    return jsonb_build_object('ok',false,'message','აირჩიე ან ჩაწერე კატეგორია');
  end if;
  if p_lat is null or p_lng is null then
    return jsonb_build_object('ok',false,'message','დააფიქსირე მიმდინარე მდებარეობა ან დასვი წერტილი რუკაზე');
  end if;

  insert into public.businesses(owner_phone,name,category,description,address,contact_phone,website,hours,image_url,lat,lng)
  values(v_phone,trim(p_name),trim(p_category),trim(coalesce(p_description,'')),trim(p_address),
    nullif(trim(coalesce(p_contact_phone,'')),''),nullif(trim(coalesce(p_website,'')),''),
    nullif(trim(coalesce(p_hours,'')),''),nullif(trim(coalesce(p_image_url,'')),''),p_lat,p_lng)
  returning id into v_id;

  return jsonb_build_object('ok',true,'id',v_id,'status','pending');
end
$function$
;

revoke all on function app_private.legacy_submit_business_application(p_phone text, p_name text, p_category text, p_description text, p_address text, p_contact_phone text, p_website text, p_hours text, p_image_url text, p_lat double precision, p_lng double precision) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.submit_business_application(p_phone text, p_name text, p_category text, p_description text, p_address text, p_contact_phone text DEFAULT NULL::text, p_website text DEFAULT NULL::text, p_hours text DEFAULT NULL::text, p_image_url text DEFAULT NULL::text, p_lat double precision DEFAULT NULL::double precision, p_lng double precision DEFAULT NULL::double precision)
 RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); return app_private.legacy_submit_business_application(p_phone,p_name,p_category,p_description,p_address,p_contact_phone,p_website,p_hours,p_image_url,p_lat,p_lng); end $guard$;
revoke all on function public.submit_business_application(p_phone text, p_name text, p_category text, p_description text, p_address text, p_contact_phone text, p_website text, p_hours text, p_image_url text, p_lat double precision, p_lng double precision) from public,anon;
grant execute on function public.submit_business_application(p_phone text, p_name text, p_category text, p_description text, p_address text, p_contact_phone text, p_website text, p_hours text, p_image_url text, p_lat double precision, p_lng double precision) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_submit_business_application_v420(p_phone text, p_name text, p_category text, p_description text, p_address text, p_website text DEFAULT NULL::text, p_hours text DEFAULT NULL::text, p_image_url text DEFAULT NULL::text, p_lat double precision DEFAULT NULL::double precision, p_lng double precision DEFAULT NULL::double precision, p_application_type text DEFAULT 'free'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_phone text:=regexp_replace(coalesce(p_phone,''),'\D','','g');
  v_id uuid; v_owner text; v_type text:=lower(trim(coalesce(p_application_type,'free')));
begin
  select full_name into v_owner from public.profiles where phone=v_phone;
  if v_owner is null then return jsonb_build_object('ok',false,'message','პროფილი ვერ მოიძებნა'); end if;
  if length(trim(coalesce(p_name,'')))<2 then return jsonb_build_object('ok',false,'message','ბიზნესის სახელი შეიყვანე'); end if;
  if length(trim(coalesce(p_category,'')))<2 then return jsonb_build_object('ok',false,'message','კატეგორია აირჩიე ან ჩაწერე'); end if;
  if length(trim(coalesce(p_address,'')))<2 then return jsonb_build_object('ok',false,'message','მისამართი შეიყვანე ან მიმდინარე მდებარეობა დააფიქსირე'); end if;
  if p_lat is null or p_lng is null then return jsonb_build_object('ok',false,'message','დააფიქსირე ობიექტის მდებარეობა'); end if;
  if v_type not in ('free','paid') then v_type:='free'; end if;

  insert into public.businesses(owner_phone,name,category,description,address,contact_phone,website,hours,image_url,lat,lng,application_type)
  values(v_phone,trim(p_name),trim(p_category),trim(coalesce(p_description,'')),trim(p_address),null,
         nullif(trim(coalesce(p_website,'')),''),nullif(trim(coalesce(p_hours,'')),''),
         nullif(trim(coalesce(p_image_url,'')),''),p_lat,p_lng,v_type)
  returning id into v_id;

  insert into public.notifications(recipient_phone,actor_phone,kind,title,body)
  select p.phone,v_phone,'business_application','🏪 ახალი ბიზნესის განაცხადი',
         v_owner||' — '||trim(p_name)||case when v_type='paid' then ' • ფასიანი' else ' • უფასო' end
  from public.profiles p
  where coalesce(p.is_super_admin,false) or p.phone='500000000'
     or p.admin_level in ('super','admin','district_admin','moderator')
     or p.account_type in ('admin','district_admin','district','moderator');

  return jsonb_build_object('ok',true,'id',v_id,'status','pending','application_type',v_type);
end $function$
;

revoke all on function app_private.legacy_submit_business_application_v420(p_phone text, p_name text, p_category text, p_description text, p_address text, p_website text, p_hours text, p_image_url text, p_lat double precision, p_lng double precision, p_application_type text) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.submit_business_application_v420(p_phone text, p_name text, p_category text, p_description text, p_address text, p_website text DEFAULT NULL::text, p_hours text DEFAULT NULL::text, p_image_url text DEFAULT NULL::text, p_lat double precision DEFAULT NULL::double precision, p_lng double precision DEFAULT NULL::double precision, p_application_type text DEFAULT 'free'::text)
 RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); return app_private.legacy_submit_business_application_v420(p_phone,p_name,p_category,p_description,p_address,p_website,p_hours,p_image_url,p_lat,p_lng,p_application_type); end $guard$;
revoke all on function public.submit_business_application_v420(p_phone text, p_name text, p_category text, p_description text, p_address text, p_website text, p_hours text, p_image_url text, p_lat double precision, p_lng double precision, p_application_type text) from public,anon;
grant execute on function public.submit_business_application_v420(p_phone text, p_name text, p_category text, p_description text, p_address text, p_website text, p_hours text, p_image_url text, p_lat double precision, p_lng double precision, p_application_type text) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_submit_specialist_announcement(p_phone text, p_contact_phone text, p_title text, p_body text, p_price numeric, p_image_url text, p_target_districts text[], p_work_hours text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_phone text:=regexp_replace(coalesce(p_phone,''),'\D','','g');
  v_name text;
  v_id uuid;
begin
  select full_name into v_name from public.profiles where phone=v_phone;
  if v_name is null then return jsonb_build_object('ok',false,'message','პროფილი ვერ მოიძებნა'); end if;
  if length(trim(coalesce(p_title,'')))=0 or length(trim(coalesce(p_body,'')))=0 then return jsonb_build_object('ok',false,'message','სათაური და აღწერა აუცილებელია'); end if;
  if coalesce(array_length(p_target_districts,1),0)=0 then return jsonb_build_object('ok',false,'message','აირჩიე მინიმუმ ერთი რაიონი'); end if;
  insert into public.specialist_announcements(owner_phone,owner_name,contact_phone,title,body,price,image_url,target_districts,work_hours)
  values(v_phone,v_name,regexp_replace(coalesce(p_contact_phone,''),'\s','','g'),trim(p_title),trim(p_body),greatest(coalesce(p_price,0),0),nullif(trim(coalesce(p_image_url,'')),''),p_target_districts,coalesce(nullif(trim(p_work_hours),''),'09:00–18:00'))
  returning id into v_id;
  return jsonb_build_object('ok',true,'id',v_id,'status','pending');
end $function$
;

revoke all on function app_private.legacy_submit_specialist_announcement(p_phone text, p_contact_phone text, p_title text, p_body text, p_price numeric, p_image_url text, p_target_districts text[], p_work_hours text) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.submit_specialist_announcement(p_phone text, p_contact_phone text, p_title text, p_body text, p_price numeric, p_image_url text, p_target_districts text[], p_work_hours text)
 RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); return app_private.legacy_submit_specialist_announcement(p_phone,p_contact_phone,p_title,p_body,p_price,p_image_url,p_target_districts,p_work_hours); end $guard$;
revoke all on function public.submit_specialist_announcement(p_phone text, p_contact_phone text, p_title text, p_body text, p_price numeric, p_image_url text, p_target_districts text[], p_work_hours text) from public,anon;
grant execute on function public.submit_specialist_announcement(p_phone text, p_contact_phone text, p_title text, p_body text, p_price numeric, p_image_url text, p_target_districts text[], p_work_hours text) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_toggle_chat_favorite(p_phone text, p_conversation_type text, p_conversation_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_phone text:=regexp_replace(coalesce(p_phone,''),'\D','','g');v_type text:=lower(trim(coalesce(p_conversation_type,'')));
begin
  if v_type not in('direct','group') then return jsonb_build_object('ok',false,'message','არასწორი დიალოგის ტიპი');end if;
  if v_type='direct' and not exists(select 1 from public.direct_chat_threads where id=p_conversation_id and v_phone in(user_a,user_b)) then return jsonb_build_object('ok',false,'message','დიალოგი ვერ მოიძებნა');end if;
  if v_type='group' and not exists(select 1 from public.live_chat_members where chat_id=p_conversation_id and phone=v_phone) then return jsonb_build_object('ok',false,'message','ჩათი ვერ მოიძებნა');end if;
  if exists(select 1 from public.chat_favorites where phone=v_phone and conversation_type=v_type and conversation_id=p_conversation_id) then
    delete from public.chat_favorites where phone=v_phone and conversation_type=v_type and conversation_id=p_conversation_id;
    return jsonb_build_object('ok',true,'favorite',false);
  end if;
  insert into public.chat_favorites(phone,conversation_type,conversation_id) values(v_phone,v_type,p_conversation_id);
  return jsonb_build_object('ok',true,'favorite',true);
end;
$function$
;

revoke all on function app_private.legacy_toggle_chat_favorite(p_phone text, p_conversation_type text, p_conversation_id uuid) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.toggle_chat_favorite(p_phone text, p_conversation_type text, p_conversation_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); return app_private.legacy_toggle_chat_favorite(p_phone,p_conversation_type,p_conversation_id); end $guard$;
revoke all on function public.toggle_chat_favorite(p_phone text, p_conversation_type text, p_conversation_id uuid) from public,anon;
grant execute on function public.toggle_chat_favorite(p_phone text, p_conversation_type text, p_conversation_id uuid) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_toggle_comment_like(p_phone text, p_comment_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_phone text:=regexp_replace(coalesce(p_phone,''),'\D','','g'); v_owner text; v_post uuid; v_liked boolean; v_count bigint;
begin
 if not exists(select 1 from public.profiles where phone=v_phone) then return jsonb_build_object('ok',false,'message','პროფილი ვერ მოიძებნა'); end if;
 select author_phone,post_id into v_owner,v_post from public.post_comments where id=p_comment_id; if v_owner is null then return jsonb_build_object('ok',false,'message','კომენტარი ვერ მოიძებნა'); end if;
 if exists(select 1 from public.comment_likes where comment_id=p_comment_id and phone=v_phone) then delete from public.comment_likes where comment_id=p_comment_id and phone=v_phone; v_liked:=false;
 else insert into public.comment_likes(comment_id,phone) values(p_comment_id,v_phone); v_liked:=true;
  if v_owner<>v_phone then insert into public.notifications(recipient_phone,actor_phone,kind,title,body,post_id,comment_id) values(v_owner,v_phone,'comment_like','შენი კომენტარი მოიწონეს',(select full_name from public.profiles where phone=v_phone),v_post,p_comment_id); end if;
 end if;
 select count(*) into v_count from public.comment_likes where comment_id=p_comment_id;
 return jsonb_build_object('ok',true,'liked',v_liked,'count',v_count);
end $function$
;

revoke all on function app_private.legacy_toggle_comment_like(p_phone text, p_comment_id uuid) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.toggle_comment_like(p_phone text, p_comment_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); return app_private.legacy_toggle_comment_like(p_phone,p_comment_id); end $guard$;
revoke all on function public.toggle_comment_like(p_phone text, p_comment_id uuid) from public,anon;
grant execute on function public.toggle_comment_like(p_phone text, p_comment_id uuid) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_toggle_daily_moment_like(p_phone text, p_moment_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v text:=public.norm_daily_phone(p_phone); n bigint;
begin
 if exists(select 1 from daily_moment_likes where moment_id=p_moment_id and phone=v) then delete from daily_moment_likes where moment_id=p_moment_id and phone=v; else insert into daily_moment_likes(moment_id,phone) values(p_moment_id,v); end if;
 select count(*) into n from daily_moment_likes where moment_id=p_moment_id; return jsonb_build_object('ok',true,'count',n);
end$function$
;

revoke all on function app_private.legacy_toggle_daily_moment_like(p_phone text, p_moment_id uuid) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.toggle_daily_moment_like(p_phone text, p_moment_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); if not exists(select 1 from public.list_daily_moments(p_phone) d where d.id=p_moment_id and not d.locked) then raise exception 'Photo unavailable' using errcode='42501'; end if; return app_private.legacy_toggle_daily_moment_like(p_phone,p_moment_id); end $guard$;
revoke all on function public.toggle_daily_moment_like(p_phone text, p_moment_id uuid) from public,anon;
grant execute on function public.toggle_daily_moment_like(p_phone text, p_moment_id uuid) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_toggle_post_like(p_phone text, p_post_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_phone text:=regexp_replace(coalesce(p_phone,''),'\D','','g'); v_owner text; v_liked boolean; v_count bigint;
begin
 if not exists(select 1 from public.profiles where phone=v_phone) then return jsonb_build_object('ok',false,'message','პროფილი ვერ მოიძებნა'); end if;
 select author_phone into v_owner from public.posts where id=p_post_id;
 if v_owner is null then return jsonb_build_object('ok',false,'message','პოსტი ვერ მოიძებნა'); end if;
 if exists(select 1 from public.post_likes where post_id=p_post_id and phone=v_phone) then delete from public.post_likes where post_id=p_post_id and phone=v_phone; v_liked:=false;
 else insert into public.post_likes(post_id,phone) values(p_post_id,v_phone); v_liked:=true;
   if v_owner<>v_phone then insert into public.notifications(recipient_phone,actor_phone,kind,title,body,post_id) values(v_owner,v_phone,'post_like','შენი პოსტი მოიწონეს',(select full_name from public.profiles where phone=v_phone),p_post_id); end if;
 end if;
 select count(*) into v_count from public.post_likes where post_id=p_post_id;
 return jsonb_build_object('ok',true,'liked',v_liked,'count',v_count);
end $function$
;

revoke all on function app_private.legacy_toggle_post_like(p_phone text, p_post_id uuid) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.toggle_post_like(p_phone text, p_post_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); return app_private.legacy_toggle_post_like(p_phone,p_post_id); end $guard$;
revoke all on function public.toggle_post_like(p_phone text, p_post_id uuid) from public,anon;
grant execute on function public.toggle_post_like(p_phone text, p_post_id uuid) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_toggle_user_block(p_phone text, p_other_phone text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_phone text:=regexp_replace(coalesce(p_phone,''),'\D','','g');v_other text:=regexp_replace(coalesce(p_other_phone,''),'\D','','g');
begin
  if v_phone='' or v_other='' or v_phone=v_other or not exists(select 1 from public.profiles where phone=v_other) then return jsonb_build_object('ok',false,'message','მომხმარებელი ვერ მოიძებნა');end if;
  if exists(select 1 from public.user_blocks where blocker_phone=v_phone and blocked_phone=v_other) then
    delete from public.user_blocks where blocker_phone=v_phone and blocked_phone=v_other;
    return jsonb_build_object('ok',true,'blocked',false);
  end if;
  insert into public.user_blocks(blocker_phone,blocked_phone) values(v_phone,v_other);
  return jsonb_build_object('ok',true,'blocked',true);
end;
$function$
;

revoke all on function app_private.legacy_toggle_user_block(p_phone text, p_other_phone text) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.toggle_user_block(p_phone text, p_other_phone text)
 RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); return app_private.legacy_toggle_user_block(p_phone,p_other_phone); end $guard$;
revoke all on function public.toggle_user_block(p_phone text, p_other_phone text) from public,anon;
grant execute on function public.toggle_user_block(p_phone text, p_other_phone text) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_update_my_business(p_phone text, p_id uuid, p_description text, p_hours text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_phone text:=regexp_replace(coalesce(p_phone,''),'\D','','g');
begin
 update public.businesses set description=trim(coalesce(p_description,'')),hours=nullif(trim(coalesce(p_hours,'')),''),updated_at=now() where id=p_id and owner_phone=v_phone;
 if not found then return jsonb_build_object('ok',false,'message','ბიზნესი ვერ მოიძებნა ან უფლება არ გაქვს'); end if;
 return jsonb_build_object('ok',true);
end $function$
;

revoke all on function app_private.legacy_update_my_business(p_phone text, p_id uuid, p_description text, p_hours text) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.update_my_business(p_phone text, p_id uuid, p_description text, p_hours text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); return app_private.legacy_update_my_business(p_phone,p_id,p_description,p_hours); end $guard$;
revoke all on function public.update_my_business(p_phone text, p_id uuid, p_description text, p_hours text) from public,anon;
grant execute on function public.update_my_business(p_phone text, p_id uuid, p_description text, p_hours text) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_update_post_content(p_phone text, p_post_id uuid, p_content text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_phone text:=regexp_replace(coalesce(p_phone,''),'\D','','g'); v_super boolean:=false;
begin
 select coalesce(is_super_admin,false) into v_super from public.profiles where phone=v_phone; if v_phone='500000000' then v_super:=true; end if;
 if length(trim(coalesce(p_content,'')))=0 then return jsonb_build_object('ok',false,'message','პოსტი ცარიელია'); end if;
 update public.posts set content=trim(p_content) where id=p_post_id and (author_phone=v_phone or v_super);
 if not found then return jsonb_build_object('ok',false,'message','რედაქტირების უფლება არ გაქვს'); end if;
 return jsonb_build_object('ok',true);
end $function$
;

revoke all on function app_private.legacy_update_post_content(p_phone text, p_post_id uuid, p_content text) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.update_post_content(p_phone text, p_post_id uuid, p_content text)
 RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); return app_private.legacy_update_post_content(p_phone,p_post_id,p_content); end $guard$;
revoke all on function public.update_post_content(p_phone text, p_post_id uuid, p_content text) from public,anon;
grant execute on function public.update_post_content(p_phone text, p_post_id uuid, p_content text) to authenticated;

CREATE OR REPLACE FUNCTION app_private.legacy_update_profile_avatar(p_phone text, p_avatar_url text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_phone text:=regexp_replace(coalesce(p_phone,''),'\D','','g');
begin
 update public.profiles set avatar_url=nullif(trim(coalesce(p_avatar_url,'')),'') where phone=v_phone;
 if not found then return jsonb_build_object('ok',false,'message','პროფილი ვერ მოიძებნა'); end if;
 return jsonb_build_object('ok',true);
end $function$
;

revoke all on function app_private.legacy_update_profile_avatar(p_phone text, p_avatar_url text) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.update_profile_avatar(p_phone text, p_avatar_url text)
 RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
begin perform app_private.assert_actor(p_phone); return app_private.legacy_update_profile_avatar(p_phone,p_avatar_url); end $guard$;
revoke all on function public.update_profile_avatar(p_phone text, p_avatar_url text) from public,anon;
grant execute on function public.update_profile_avatar(p_phone text, p_avatar_url text) to authenticated;

create or replace function public.can_manage_business_ads(p_phone text) returns boolean language sql stable security definer set search_path='' as $$select exists(select 1 from public.profiles p where p.phone=regexp_replace(coalesce(p_phone,''),'\D','','g') and (p.is_super_admin or p.admin_level in ('super','admin')))$$;

notify pgrst,'reload schema';
commit;