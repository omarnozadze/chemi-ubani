-- Additive SMS/push preparation. Does not secure or replace every legacy API.
create schema if not exists app_private;
revoke all on schema app_private from public,anon;
grant usage on schema app_private to authenticated;
create or replace function app_private.verified_phone()
returns text language plpgsql security definer set search_path='' as $$
declare p text;
begin
 if auth.uid() is null then raise exception 'SMS verification required' using errcode='42501'; end if;
 select regexp_replace(u.phone,'\D','','g') into p from auth.users u
 where u.id=auth.uid() and u.phone_confirmed_at is not null
 and exists(select 1 from auth.sessions s where s.user_id=u.id and s.id::text=auth.jwt()->>'session_id');
 if p is null or p !~ '^9955[0-9]{8}$' then raise exception 'Verified Georgian phone required' using errcode='42501'; end if;
 return substring(p from 4);
end $$;
revoke all on function app_private.verified_phone() from public,anon;
grant execute on function app_private.verified_phone() to authenticated;
create or replace function app_private.get_verified_profile()
returns jsonb language plpgsql security definer set search_path='' as $$
declare p text:=app_private.verified_phone(); result jsonb;
begin
 select jsonb_build_object('id',id,'phone',phone,'full_name',full_name,'district',district,'neighborhood',neighborhood,'city',city,'account_type',account_type,'is_super_admin',is_super_admin,'admin_level',admin_level,'avatar_url',avatar_url) into result from public.profiles where phone=p;
 return result;
end $$;
create or replace function public.get_verified_profile()
returns jsonb language sql security invoker set search_path='' as $$select app_private.get_verified_profile()$$;
create or replace function app_private.register_verified_profile(p_full_name text,p_district text,p_neighborhood text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare p text:=app_private.verified_phone();
begin
 if length(trim(p_full_name))<1 or length(p_full_name)>150 then raise exception 'Invalid name';end if;
 insert into public.profiles(phone,full_name,district,neighborhood,auth_user_id,phone_verified_at,is_super_admin)
 values(p,trim(p_full_name),p_district,p_neighborhood,auth.uid(),now(),false);
 return jsonb_build_object('ok',true);
exception when unique_violation then return jsonb_build_object('ok',false,'code','phone_exists');
end $$;
create or replace function public.sms_register_profile(p_full_name text,p_district text default null,p_neighborhood text default null)
returns jsonb language sql security invoker set search_path='' as $$select app_private.register_verified_profile(p_full_name,p_district,p_neighborhood)$$;
create or replace function app_private.register_push_device(p_phone text,p_token text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare p text:=app_private.verified_phone();
begin
 if p<>regexp_replace(p_phone,'\D','','g') then raise exception 'Phone mismatch' using errcode='42501'; end if;
 if p_token is null or p_token !~ '^(ExponentPushToken|ExpoPushToken)\[[A-Za-z0-9_-]+\]$' or length(p_token)>250 then raise exception 'Invalid token';end if;
 if not exists(select 1 from public.profiles where phone=p) then raise exception 'Profile required';end if;
 insert into public.push_devices(token,phone) values(p_token,p)
 on conflict(token) do update set updated_at=now() where public.push_devices.phone=p;
 if not found then raise exception 'Token belongs to another account' using errcode='42501';end if;
 return jsonb_build_object('ok',true);
end $$;
create or replace function public.register_push_device(p_phone text,p_token text)
returns jsonb language sql security invoker set search_path='' as $$select app_private.register_push_device(p_phone,p_token)$$;
create or replace function app_private.unregister_push_device(p_token text default null)
returns void language plpgsql security definer set search_path='' as $$
declare p text:=app_private.verified_phone();
begin delete from public.push_devices where phone=p and (p_token is null or token=p_token);end $$;
create or replace function public.unregister_push_device(p_token text)
returns void language sql security invoker set search_path='' as $$select app_private.unregister_push_device(p_token)$$;
create or replace function public.unregister_my_push_devices()
returns void language sql security invoker set search_path='' as $$select app_private.unregister_push_device(null)$$;
revoke all on function app_private.get_verified_profile(),app_private.register_verified_profile(text,text,text),app_private.register_push_device(text,text),app_private.unregister_push_device(text) from public,anon;
grant execute on function app_private.get_verified_profile(),app_private.register_verified_profile(text,text,text),app_private.register_push_device(text,text),app_private.unregister_push_device(text) to authenticated;
revoke all on function public.get_verified_profile(),public.sms_register_profile(text,text,text),public.register_push_device(text,text),public.unregister_push_device(text),public.unregister_my_push_devices() from public,anon;
grant execute on function public.get_verified_profile(),public.sms_register_profile(text,text,text),public.register_push_device(text,text),public.unregister_push_device(text),public.unregister_my_push_devices() to authenticated;
notify pgrst,'reload schema';
