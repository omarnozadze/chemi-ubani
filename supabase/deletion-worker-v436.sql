-- Separate worker credential, stored only in Vault. Never log the secret.
do $$begin if not exists(select 1 from vault.secrets where name='deletion_worker_v436')then perform vault.create_secret(gen_random_uuid()::text||gen_random_uuid()::text,'deletion_worker_v436');end if;end$$;
create function public.deletion_worker_authorized_v436(p_secret text)returns boolean language sql security definer set search_path=''as $$select length(p_secret)between 64 and 128 and exists(select 1 from vault.decrypted_secrets where name='deletion_worker_v436'and decrypted_secret=p_secret)$$;
revoke all on function public.deletion_worker_authorized_v436(text)from public,anon,authenticated;grant execute on function public.deletion_worker_authorized_v436(text)to service_role;
create table app_private.deletion_worker_clock_v436(id boolean primary key default true check(id),last_run timestamptz not null default '-infinity');
alter table app_private.deletion_worker_clock_v436 enable row level security;revoke all on app_private.deletion_worker_clock_v436 from public,anon,authenticated;
insert into app_private.deletion_worker_clock_v436(id)values(true);
create function public.deletion_worker_claim_v436()returns boolean language plpgsql security definer set search_path=''as $$declare n integer;begin update app_private.deletion_worker_clock_v436 set last_run=now()where id and last_run<now()-interval '60 seconds';get diagnostics n=row_count;return n=1;end$$;
revoke all on function public.deletion_worker_claim_v436()from public,anon,authenticated;grant execute on function public.deletion_worker_claim_v436()to service_role;
select cron.schedule('deletion-worker-v436','* * * * *',$job$
 select net.http_post(url:='https://exampleprojectref0000.supabase.co/functions/v1/deletion-worker',headers:=jsonb_build_object('Content-Type','application/json','Authorization','Bearer YOUR_SUPABASE_ANON_KEY','x-deletion-worker',(select decrypted_secret from vault.decrypted_secrets where name='deletion_worker_v436')),body:='{}'::jsonb,timeout_milliseconds:=55000);
$job$);
notify pgrst,'reload schema';
