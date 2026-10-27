begin;
create table if not exists public.business_ratings(
 business_id uuid not null references public.businesses(id) on delete cascade,
 phone text not null references public.profiles(phone) on delete cascade,
 rating integer not null check(rating between 1 and 5),comment text check(length(comment)<=2000),
 updated_at timestamptz not null default now(),primary key(business_id,phone)
);
alter table public.business_ratings enable row level security;
revoke all on public.business_ratings from public,anon,authenticated;
create or replace function public.rate_business(p_phone text,p_business_id uuid,p_rating integer,p_comment text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
begin
 perform app_private.assert_actor(p_phone);
 if p_rating is null or p_rating<1 or p_rating>5 or length(p_comment)>2000 then raise exception 'Invalid rating';end if;
 if not exists(select 1 from public.businesses where id=p_business_id and status='approved' and owner_phone<>app_private.verified_phone())then raise exception 'Cannot rate this business' using errcode='42501';end if;
 insert into public.business_ratings(business_id,phone,rating,comment)values(p_business_id,app_private.verified_phone(),p_rating,nullif(trim(p_comment),''))
 on conflict(business_id,phone)do update set rating=excluded.rating,comment=excluded.comment,updated_at=now();
 return jsonb_build_object('ok',true);
end $$;
create or replace function public.list_business_rating_summaries()
returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;begin
 perform app_private.verified_phone();
 select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb)into result from(
 select b.id,count(r.phone)rating_count,avg(r.rating)avg_rating from public.businesses b left join public.business_ratings r on r.business_id=b.id
 where b.status='approved' group by b.id)x;return result;
end $$;
create or replace function public.profile_business_rating(p_phone text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;begin
 perform app_private.assert_actor(p_phone);
 select jsonb_build_object('business_count',count(distinct b.id),'rating_count',count(r.phone),'avg_rating',avg(r.rating))into result
 from public.businesses b left join public.business_ratings r on r.business_id=b.id where b.owner_phone=app_private.verified_phone()and b.status='approved';return result;
end $$;
revoke all on function public.rate_business(text,uuid,integer,text),public.list_business_rating_summaries(),public.profile_business_rating(text)from public,anon;
grant execute on function public.rate_business(text,uuid,integer,text),public.list_business_rating_summaries(),public.profile_business_rating(text)to authenticated;
notify pgrst,'reload schema';
commit;
