-- Supabase pg_cron runs in UTC. These bounded batches cover Georgia 08:00 and 20:00.
-- Every-minute drain within each slot; notification source_event prevents duplicate reminders.
select cron.schedule('daily-photo-reminders','* 4,16 * * *',$$select app_private.enqueue_daily_photo_reminders();$$);
