-- Private, receive-only invalidation channel. Contains neither phone nor message content.
create policy activity_owner_receive on realtime.messages for select to authenticated using(extension='broadcast'and realtime.topic()='activity:'||(select auth.uid())::text);
create or replace function app_private.broadcast_activity()returns trigger language plpgsql security definer set search_path='' as $$
declare recipient uuid;begin
 select id into recipient from auth.users where phone='995'||new.recipient_phone and phone_confirmed_at is not null limit 1;
 if recipient is not null then perform realtime.send('{}'::jsonb,'activity','activity:'||recipient::text,true);end if;
 return new;
 exception when others then return new; -- periodic RPC reconciliation remains available
end$$;
revoke all on function app_private.broadcast_activity()from public,anon,authenticated;
create trigger activity_realtime_signal after insert on public.notifications for each row execute function app_private.broadcast_activity();
