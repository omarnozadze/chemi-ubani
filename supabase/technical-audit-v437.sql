-- Storage RLS records function OIDs. v436 renamed the prior guard, leaving this
-- policy bound to the revoked old function. Use the stable public wrapper.
alter policy chat_files_upload_v432 on storage.objects to authenticated with check(
 bucket_id='chat-files' and split_part(name,'/',1)=(select public.current_verified_phone())
 and name ~ '^[0-9]+/[0-9a-f-]{36}\.[a-z0-9]+$'
);
notify pgrst,'reload schema';
