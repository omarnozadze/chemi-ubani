-- Audited small tables (< 128 KiB each): fail quickly rather than wait on live locks.
set local lock_timeout='3s';
set local statement_timeout='20s';
create index if not exists campaign_batches_v439_actor_v443 on app_private.campaign_batches_v439(actor);
create index if not exists content_requests_v439_actor_v443 on app_private.content_requests_v439(actor);
create index if not exists group_mutes_v440_chat_id_v443 on app_private.group_mutes_v440(chat_id);
create index if not exists service_batches_v439_actor_v443 on app_private.service_batches_v439(actor);
create index if not exists business_banners_business_id_v443 on public.business_banners(business_id);
create index if not exists business_banners_created_by_v443 on public.business_banners(created_by);
create index if not exists business_premium_requests_owner_phone_v443 on public.business_premium_requests(owner_phone);
create index if not exists business_ratings_phone_v443 on public.business_ratings(phone);
create index if not exists comment_likes_phone_v443 on public.comment_likes(phone);
create index if not exists daily_moment_comments_phone_v443 on public.daily_moment_comments(phone);
create index if not exists daily_moment_likes_phone_v443 on public.daily_moment_likes(phone);
create index if not exists direct_chat_messages_sender_phone_v443 on public.direct_chat_messages(sender_phone);
create index if not exists direct_messages_recipient_phone_v443 on public.direct_messages(recipient_phone);
create index if not exists hot_news_author_phone_v443 on public.hot_news(author_phone);
create index if not exists live_chat_messages_sender_phone_v443 on public.live_chat_messages(sender_phone);
create index if not exists live_chats_owner_phone_v443 on public.live_chats(owner_phone);
create index if not exists marketplace_listings_owner_phone_v443 on public.marketplace_listings(owner_phone);
create index if not exists notifications_comment_id_v443 on public.notifications(comment_id);
create index if not exists notifications_post_id_v443 on public.notifications(post_id);
create index if not exists post_comments_author_phone_v443 on public.post_comments(author_phone);
create index if not exists post_likes_phone_v443 on public.post_likes(phone);
create index if not exists service_order_reviews_customer_phone_v443 on public.service_order_reviews(customer_phone);
create index if not exists user_reports_reported_phone_v443 on public.user_reports(reported_phone);
create index if not exists user_reports_reporter_phone_v443 on public.user_reports(reporter_phone);
-- Keep the original equivalent index; do not remove any data or constraint.
do $$begin
 if exists(select 1 from pg_index a join pg_index b on a.indrelid=b.indrelid and a.indkey=b.indkey and a.indclass=b.indclass and a.indcollation=b.indcollation and a.indoption=b.indoption where a.indexrelid=to_regclass('public.profiles_city_district') and b.indexrelid=to_regclass('public.profiles_city_district_v432') and a.indisvalid and not b.indisunique and a.indpred is null and b.indpred is null and a.indexprs is null and b.indexprs is null and not exists(select 1 from pg_constraint c where c.conindid=b.indexrelid))then
 drop index public.profiles_city_district_v432;
 end if;
end$$;
-- Enforce limits on new image uploads at the server, including modified clients.
-- Existing objects, visibility and ownership policies are unchanged.
update storage.buckets set file_size_limit=least(coalesce(file_size_limit,10485760),10485760),allowed_mime_types=array['image/jpeg','image/png','image/webp','image/gif']
where id in('post-images','specialist-images','marketplace-images','business-images','profile-images','banner-images','chat-images','day-images','daily-moments');
