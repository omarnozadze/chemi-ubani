
-- Erase new retry ledgers along with the account.
alter table app_private.campaign_batches_v439 add constraint campaign_batches_v439_actor_fk foreign key(actor)references public.profiles(phone)on delete cascade;
alter table app_private.service_batches_v439 add constraint service_batches_v439_actor_fk foreign key(actor)references public.profiles(phone)on delete cascade;
alter table app_private.content_requests_v439 add constraint content_requests_v439_actor_fk foreign key(actor)references public.profiles(phone)on delete cascade;
