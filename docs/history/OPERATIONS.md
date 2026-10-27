> ისტორიული ჩანაწერი: წინა გამოშვებები. მიმდინარე v4.32-ის სტატუსისთვის იხილეთ READ-ME-FIRST-ka.md და VERIFICATION-v432.md. v4.32-ის სერვერული ცვლილებები არ დაყენებულა.

# v4.31 operational note

Migration 20260916063037_conditional_daily_photo_reminders_v431 is deployed. The public preference RPC is invoker-only; the private implementation binds to verified_phone(). Raw preferences have RLS and no direct client access. Existing user preferences are not backfilled: the new client registers its setting after login. Legacy local reminders are cancelled when the new native app mounts and again through the WebView bridge.

Cron daily-photo-reminders runs `* 4,16 * * *` in verified GMT, corresponding to Georgia 08:00/20:00. Each minute enqueues up to 2000 eligible accounts. The unique recipient/source event prevents repeats within the slot. Both confirmed daily_moments and my_day_posts are checked using Georgia calendar-day boundaries. Category/global/quiet preferences and a registered device are required. The worker checks eligibility again before delivery; a new photo, reminder opt-out or expired hourly slot suppresses pending work. A push already handed to the provider cannot be recalled.

This is a twice-daily clock schedule, not 12 hours after the user's last login. Queue/provider delays may shift delivery within the hour. The existing worker throughput has NOT been validated at 20–30k concurrent users; this feature is not a capacity claim.

Rollback: pause ONLY daily-photo-reminders in Supabase Cron before reverting to an older client with unconditional local reminders. Keep the new preference table and RPCs; do not delete data. The new push eligibility and notification resolution remain compatible with all existing notification kinds.

Local tests never invoke production enqueue/worker functions or send real pushes. Live verification covered schema privileges, job schedule/active state and GMT timezone. On-device visual rendering and end-to-end scheduled delivery remain to be checked after rebuilding the APK.

# v4.30 location update

Migration 20260916060551_nearby_businesses_v430 adds a read-only authenticated nearby query and an approved-business latitude index. Client rollback to v4.29 leaves these unused and requires no schema rollback. Search origins are session-only, cleared on logout and not written to profiles. The selected coordinates are sent to the nearby RPC and OSM query; navigation sends its route to Google Maps only on the route action.

The 200-row cap applies after the spatial filter and distance ordering. Ratings aggregate only for returned businesses. Dense results show an overflow hint. No geocoding API or paid routing SDK was added. Existing Leaflet is reused.

# v4.29 operational note

Migration 20260916054225_conversation_targets_replies_v429 is deployed. It adds nullable reply references plus is_reply markers and authenticated target/search/reply APIs. The old send_chat_message_verified API is unchanged; reverting the client to v4.28 does not require destructive schema rollback. Do not drop reply columns or delete messages as a rollback. Older clients can still read message rows with extra fields. New quoted replies require the v4.29 client.

No data was backfilled and no real messages were sent as tests. Cursor pages return at most 25 search results or 50 history rows. Monitor search latency before large-scale rollout.

# Operations / recovery — 4.28.0

## Current deployment
Project: exampleprojectref0000. Edge activity-push version 6 uses custom Vault-secret authorization; manual receipts additionally accept a verified superadmin session. There is no client service-role key.
Cron jobs: activity-push-drain (10 seconds), activity-push-receipts (minute), app-operational-cleanup (daily). Last tick only proves the scheduler ran; pending age, HTTP error status and receipts must also be observed. The queue has no historical backfill.

## Observability
Admin → notification diagnostics: waiting count, 24h failed/unknown, last tick/error, masked recipient. A rising queue age or WorkerHttpError requires inspection of Edge logs and FCM credentials. Do not automatically reset unknown deliveries to retry. Expo tickets and FCM/APNs acceptance do not prove screen display.
Realtime only publishes an empty invalidation signal to activity:<auth-user-id>; private receive policy binds it to auth.uid. Authenticated clients have no broadcast write policy. Conversation data still uses verified RPC membership. It reconnects with jitter/backoff, disconnects in background/logout, and reconciles periodically even when connected.

## Rollback
Keep the previous source ZIP and working APK. To revert client behavior, build the previous client source with a versionCode greater than the installed one using the SAME signing key. Do not uninstall first if device-only drafts matter. Current SQL changes are additive and retain old RPC signatures; the old client can continue using them.
For a server incident, pause only the affected cron job in Supabase Cron while investigating; pending rows remain in the database. Resume after the fix. Do not delete delivery rows, resubmit all notifications or roll back database tables to restore a UI. A former Edge implementation is retained as reference in activity-push-v5.ts, not an automatic rollback: it does not process the new queue.

## Backups before public launch
Check the actual project's Database → Backups retention and restore options. Backups/PITR may require a paid setting; none was purchased or asserted enabled here. Arrange a database backup and a separate Storage-object copy. Keep signing keystore and service-account keys in private encrypted backups, never a public repository. Rehearse restore in an isolated project before relying on a recovery claim. No restore into the live project was attempted.
Official guidance: https://supabase.com/docs/guides/platform/backups

## Remaining capacity work
100/100 prior manual requests is a small functional sample, not evidence for 20–30k concurrent users. Deferred: realistic authenticated multi-user load, Realtime connection/message quotas, database compute sizing, storage egress and notification fanout load. No plan/compute spending was changed. Search is bounded to 25 rows but uses substring matching and may scan many posts; inspect its plan on representative data before scale. Legacy list RPCs remain for compatibility; new clients use cursor pages.

## Advisory interpretation
New raw tables deliberately deny direct client reads/writes; verified functions expose only appropriate results. This produces RLS-no-policy informational notices. The definer-function notices require ongoing review of each actor/admin gate, not blanket grants. Remaining missing-FK-index notices were not blindly indexed without workload evidence; unused indexes were not removed from this small database. Password breach protection warning remains; this app currently authenticates via SMS.
https://supabase.com/docs/guides/database/database-linter?lint=0001_unindexed_foreign_keys
https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable

## Test boundary
Local PGlite fixtures and mocked WebView/provider/socket tests verify logic, access denial, races and regression behavior. They do not verify Android rendering, real network delivery, production throughput or live restore. Live checks verified migrations, Edge ACTIVE state, cron running without failed jobs, closed worker/client privileges and private broadcast receive policy. Direct manual worker invocation was rejected by automatic approval review because it could send real pushes; no workaround was attempted.
