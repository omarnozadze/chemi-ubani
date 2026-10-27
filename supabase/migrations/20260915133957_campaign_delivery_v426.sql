begin;
-- A bounded diagnostic ledger. No message bodies or raw push tokens are stored here.
create table public.push_delivery_log(
 id uuid primary key default gen_random_uuid(),notification_id uuid not null references public.notifications(id) on delete cascade,
 device_key text not null,recipient_phone text not null,state text not null check(state in('processing','accepted','provider_accepted','failed','suppressed','no_device','unknown','receipt_expired')),
 error_code text check(error_code is null or error_code~'^[A-Za-z0-9_]{1,60}$'),receipt_id text check(receipt_id is null or length(receipt_id)<=150),
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),unique(notification_id,device_key)
);
create index push_delivery_recent on public.push_delivery_log(created_at desc);
create index push_delivery_receipts on public.push_delivery_log(created_at)where state='accepted';
alter table public.push_delivery_log enable row level security;
revoke all on public.push_delivery_log from public,anon,authenticated;
grant select,insert,update,delete on public.push_delivery_log to service_role;
create function app_private.admin_push_diagnostics(p_state text default null)returns jsonb language plpgsql security definer set search_path='' as $$
declare actor text:=app_private.verified_phone();begin
 if not exists(select 1 from public.profiles where phone=actor and(is_super_admin or admin_level='super'))then raise exception 'Administrator required'using errcode='42501';end if;
 return(select coalesce(jsonb_agg(to_jsonb(r)),'[]')from(
 select x.id,x.notification_id,n.kind,'***'||right(x.recipient_phone,4)recipient,
 case when x.state='processing'and x.created_at<now()-interval '5 minutes'then 'unknown' when x.state='accepted'and x.created_at<now()-interval '24 hours'then 'receipt_expired'else x.state end state,x.error_code,x.created_at,x.updated_at
 from public.push_delivery_log x join public.notifications n on n.id=x.notification_id where x.created_at>=now()-interval '30 days'
 and(p_state is null or(case when x.state='processing'and x.created_at<now()-interval '5 minutes'then 'unknown'when x.state='accepted'and x.created_at<now()-interval '24 hours'then 'receipt_expired'else x.state end)=p_state)order by x.created_at desc,x.id desc limit 100)r);
end $$;
create function public.admin_push_diagnostics(p_state text default null)returns jsonb language sql security invoker set search_path='' as $$select app_private.admin_push_diagnostics(p_state)$$;
revoke all on function app_private.admin_push_diagnostics(text),public.admin_push_diagnostics(text)from public,anon;
grant execute on function app_private.admin_push_diagnostics(text),public.admin_push_diagnostics(text)to authenticated;

alter table public.admin_campaigns add column revision integer not null default 1;
create function app_private.edit_admin_campaign(p_id uuid,p_revision integer,p_title text,p_body text,p_image_url text)returns jsonb language plpgsql security definer set search_path='' as $$
declare actor text:=app_private.verified_phone();c public.admin_campaigns%rowtype;begin
 if not exists(select 1 from public.profiles where phone=actor and(is_super_admin or admin_level='super'))then raise exception 'Administrator required'using errcode='42501';end if;
 if p_title is null or length(trim(p_title))not between 1 and 160 or p_body is null or length(trim(p_body))not between 1 and 5000 then raise exception 'Invalid content';end if;
 if nullif(p_image_url,'')is not null and(p_image_url!~'^https://'or length(p_image_url)>3000)then raise exception 'Invalid image';end if;
 select * into c from public.admin_campaigns where id=p_id and status<>'deleted'for update;
 if not found then raise exception 'Campaign not found';end if;
 -- Lost-response retries are successful without another write or revision bump.
 if c.title=trim(p_title)and c.body=trim(p_body)and c.image_url is not distinct from nullif(p_image_url,'')then return jsonb_build_object('ok',true,'id',c.id,'revision',c.revision);end if;
 if p_revision is null or c.revision<>p_revision then return jsonb_build_object('ok',false,'code','conflict');end if;
 update public.admin_campaigns set title=trim(p_title),body=trim(p_body),image_url=nullif(p_image_url,''),revision=revision+1 where id=c.id returning * into c;
 update public.hot_news set title=c.title,body=c.body,image_url=c.image_url where campaign_id=c.id;
 return jsonb_build_object('ok',true,'id',c.id,'revision',c.revision);
end $$;
create function public.edit_admin_campaign(p_id uuid,p_revision integer,p_title text,p_body text,p_image_url text)returns jsonb language sql security invoker set search_path='' as $$select app_private.edit_admin_campaign(p_id,p_revision,p_title,p_body,p_image_url)$$;
revoke all on function app_private.edit_admin_campaign(uuid,integer,text,text,text),public.edit_admin_campaign(uuid,integer,text,text,text)from public,anon;
grant execute on function app_private.edit_admin_campaign(uuid,integer,text,text,text),public.edit_admin_campaign(uuid,integer,text,text,text)to authenticated;
create or replace function public.list_admin_campaigns()
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor text:=app_private.verified_phone();result jsonb;begin
 select coalesce(jsonb_agg(to_jsonb(x)order by x.created_at desc),'[]'::jsonb)into result from(
 select c.id,c.title,c.body,c.category,c.placement,c.city,c.target_districts,c.neighborhood,c.image_url,c.status,c.created_at,c.expires_at,c.revision from public.admin_campaigns c join public.profiles p on p.phone=actor
 where c.status<>'deleted'and((p.is_super_admin or p.admin_level='super')or(c.status='active'and c.expires_at>now()and c.city=p.city and p.district=any(c.target_districts)and(c.neighborhood is null or c.neighborhood=p.neighborhood)))order by c.created_at desc limit 100)x;return result;end $$;
revoke all on function public.list_admin_campaigns()from public,anon;grant execute on function public.list_admin_campaigns()to authenticated;
notify pgrst,'reload schema';
commit;
