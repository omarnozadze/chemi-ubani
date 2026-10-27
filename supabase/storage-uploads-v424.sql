-- Only verified users can create objects in their own phone-number folder.
-- Existing public image viewing remains unchanged; no objects are deleted.
begin;
create or replace function public.current_verified_phone() returns text language sql security definer set search_path='' as $$select app_private.verified_phone()$$;
revoke all on function public.current_verified_phone() from public,anon;
grant execute on function public.current_verified_phone() to authenticated;
drop policy if exists "daily moments upload" on storage.objects;
drop policy if exists "day images prototype upload" on storage.objects;
drop policy if exists "banner images prototype upload" on storage.objects;
drop policy if exists "profile images prototype upload" on storage.objects;
drop policy if exists "business images prototype upload" on storage.objects;
drop policy if exists "marketplace images upload" on storage.objects;
drop policy if exists "chat images prototype upload" on storage.objects;
drop policy if exists "specialist images prototype upload" on storage.objects;
drop policy if exists "post images prototype upload" on storage.objects;
drop policy if exists "verified image upload" on storage.objects;
create policy "verified image upload" on storage.objects for insert to authenticated with check(
 bucket_id in ('daily-moments','day-images','banner-images','profile-images','business-images','marketplace-images','chat-images','specialist-images','post-images')
 and split_part(name,'/',1)=(select public.current_verified_phone())
);
commit;
