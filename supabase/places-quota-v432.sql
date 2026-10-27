create table app_private.places_quota_v432(actor text not null,slot timestamptz not null,hits integer not null,primary key(actor,slot));
alter table app_private.places_quota_v432 enable row level security;revoke all on app_private.places_quota_v432 from public,anon,authenticated;
create function app_private.places_quota_v432()returns boolean language plpgsql security definer set search_path=''as $$declare v_actor text:=app_private.verified_phone();v_slot timestamptz:=date_trunc('hour',now());counted integer;begin
 perform pg_advisory_xact_lock(432,1);
 delete from app_private.places_quota_v432 q where q.slot<v_slot-interval '2 hours';
 if(select coalesce(sum(hits),0)from app_private.places_quota_v432 q where q.slot=v_slot)>=1000 then return false;end if;
 select hits into counted from app_private.places_quota_v432 q where q.actor=v_actor and q.slot=v_slot;if coalesce(counted,0)>=10 then return false;end if;
 insert into app_private.places_quota_v432 values(v_actor,v_slot,1)on conflict(actor,slot)do update set hits=app_private.places_quota_v432.hits+1;return true;end$$;
create function public.places_quota_v432()returns boolean language sql security invoker set search_path=''as $$select app_private.places_quota_v432()$$;
revoke all on function public.places_quota_v432(),app_private.places_quota_v432()from public,anon;grant execute on function public.places_quota_v432(),app_private.places_quota_v432()to authenticated;
