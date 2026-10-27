create extension if not exists pg_cron;
create or replace function app_private.tick_push_worker(p_receipts boolean default false)returns void language plpgsql security definer set search_path='' as $$
declare secret text;begin
 update app_private.worker_clock set last_tick=now(),last_error=null where id;
 if p_receipts then
 if not exists(select 1 from public.push_delivery_log where state='accepted'and created_at<now()-interval '15 minutes')then return;end if;
 else
 if not exists(select 1 from public.push_delivery_log where(state in('pending','retry')and next_attempt_at<=now())or(state in('leased','processing')and lease_until<now()))then return;end if;
 end if;
 select decrypted_secret into secret from vault.decrypted_secrets where name='activity_push_webhook_secret'limit 1;
 if secret is null then update app_private.worker_clock set last_error='MissingSecret'where id;return;end if;
 perform net.http_post(url:='https://exampleprojectref0000.supabase.co/functions/v1/activity-push',headers:=jsonb_build_object('Content-Type','application/json','x-webhook-secret',secret),body:=jsonb_build_object('action',case when p_receipts then 'check_receipts'else 'drain'end),timeout_milliseconds:=25000);
 exception when others then update app_private.worker_clock set last_tick=now(),last_error='WorkerRequestFailed'where id;
end $$;
revoke all on function app_private.tick_push_worker(boolean)from public,anon,authenticated;
select cron.schedule('activity-push-drain','10 seconds',$cron$select app_private.tick_push_worker(false)$cron$);
select cron.schedule('activity-push-receipts','* * * * *',$cron$select app_private.tick_push_worker(true)$cron$);
select cron.schedule('app-operational-cleanup','15 2 * * *',$cron$
 delete from public.push_delivery_log where created_at<now()-interval '30 days';
 delete from public.app_errors where created_at<now()-interval '30 days';
 delete from app_private.write_limits where window_at<now()-interval '1 day';
 delete from cron.job_run_details where end_time<now()-interval '7 days';
$cron$);
