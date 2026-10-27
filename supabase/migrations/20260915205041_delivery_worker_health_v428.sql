alter table app_private.worker_clock add column last_request bigint,add column last_request_at timestamptz,add column last_http_status integer;
create or replace function app_private.tick_push_worker(p_receipts boolean default false)returns void language plpgsql security definer set search_path='' as $$
declare secret text;request_id bigint;clock app_private.worker_clock%rowtype;response record;begin
 update app_private.worker_clock set last_tick=now() where id returning * into clock;
 if clock.last_request is not null then
 select status_code,timed_out into response from net._http_response where id=clock.last_request;
 if found then update app_private.worker_clock set last_http_status=response.status_code,last_error=case when response.timed_out or response.status_code is null or response.status_code not between 200 and 299 then 'WorkerHttpError'else null end,last_request=null where id;
 elsif clock.last_request_at>now()-interval '30 seconds'then return;
 else update app_private.worker_clock set last_error='WorkerTimeout',last_request=null where id;end if;
 end if;
 if p_receipts then
 if not exists(select 1 from public.push_delivery_log where state='accepted'and created_at<now()-interval '15 minutes')then return;end if;
 else
 if not exists(select 1 from public.push_delivery_log where(state in('pending','retry')and next_attempt_at<=now())or(state in('leased','processing')and lease_until<now()))then return;end if;
 end if;
 select decrypted_secret into secret from vault.decrypted_secrets where name='activity_push_webhook_secret'limit 1;
 if secret is null then update app_private.worker_clock set last_error='MissingSecret'where id;return;end if;
 select net.http_post(url:='https://exampleprojectref0000.supabase.co/functions/v1/activity-push',headers:=jsonb_build_object('Content-Type','application/json','x-webhook-secret',secret),body:=jsonb_build_object('action',case when p_receipts then 'check_receipts'else 'drain'end),timeout_milliseconds:=25000)into request_id;
 update app_private.worker_clock set last_request=request_id,last_request_at=now()where id;
 exception when others then update app_private.worker_clock set last_tick=now(),last_error='WorkerRequestFailed'where id;
end $$;
revoke all on function app_private.tick_push_worker(boolean)from public,anon,authenticated;
