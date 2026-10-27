
create extension if not exists pg_net with schema extensions;
create table if not exists public.push_devices(token text primary key, phone text not null references public.profiles(phone) on delete cascade, updated_at timestamptz not null default now());
alter table public.push_devices enable row level security;
revoke all on public.push_devices from public, anon, authenticated;
grant select,insert,update,delete on public.push_devices to service_role;
do $$ begin
 if not exists(select 1 from vault.secrets where name='activity_push_webhook_secret') then
  perform vault.create_secret(encode(extensions.gen_random_bytes(32),'hex'),'activity_push_webhook_secret','Internal activity-push webhook authentication');
 end if;
end $$;
create or replace function public.verify_activity_push_secret(p_secret text)
returns boolean language sql security definer set search_path='' as $$
 select coalesce((select extensions.digest(p_secret,'sha256') = extensions.digest(decrypted_secret,'sha256') from vault.decrypted_secrets where name='activity_push_webhook_secret' limit 1),false);
$$;
revoke all on function public.verify_activity_push_secret(text) from public,anon,authenticated;
grant execute on function public.verify_activity_push_secret(text) to service_role;
notify pgrst,'reload schema';

create or replace function public.dispatch_activity_push()
returns trigger language plpgsql security definer set search_path='' as $$
declare s text;
begin
 select decrypted_secret into s from vault.decrypted_secrets where name='activity_push_webhook_secret' limit 1;
 if s is null then raise warning 'Activity push secret unavailable'; return new; end if;
 perform net.http_post(
 url:='https://exampleprojectref0000.supabase.co/functions/v1/activity-push',
 headers:=jsonb_build_object('Content-Type','application/json','x-webhook-secret',s),
 body:=jsonb_build_object('type','INSERT','schema','public','table','notifications','record',jsonb_build_object('id',new.id)),
 timeout_milliseconds:=10000);
 return new;
exception when others then
 raise warning 'Activity push enqueue failed';
 return new;
end;
$$;
revoke all on function public.dispatch_activity_push() from public,anon,authenticated;
create trigger activity_push_after_insert after insert on public.notifications for each row execute function public.dispatch_activity_push();
