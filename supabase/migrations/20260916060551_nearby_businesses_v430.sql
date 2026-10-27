-- Additive bounded nearest-business API. Raw tables remain closed to client roles.
create index if not exists businesses_approved_latitude on public.businesses(lat)where status='approved'and lat is not null and lng is not null;
create or replace function app_private.nearby_businesses(p_lat double precision,p_lng double precision,p_radius double precision)returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor text:=app_private.verified_phone();result jsonb;begin
 if p_lat is null or p_lng is null or p_radius is null or not(p_lat between -90 and 90)or not(p_lng between -180 and 180)or not(p_radius between 0.5 and 5)then raise exception 'Invalid search coordinates or radius'using errcode='22023';end if;
 with candidates as materialized(
 select b.id,b.name,b.category,b.description,b.address,b.contact_phone,b.website,b.hours,b.image_url,b.lat,b.lng,b.is_premium,
  12742.0*asin(sqrt(least(1.0,greatest(0.0,power(sin(radians(b.lat-p_lat)/2),2)+cos(radians(p_lat))*cos(radians(b.lat))*power(sin(radians(b.lng-p_lng)/2),2)))))distance_km
 from public.businesses b where b.status='approved'and b.lat is not null and b.lng is not null and b.lat between greatest(-90,p_lat-p_radius/111.0)and least(90,p_lat+p_radius/111.0)and b.lng between -180 and 180
 ),nearest as materialized(select * from candidates where distance_km<=p_radius order by distance_km,id limit 201),page as(select * from nearest order by distance_km,id limit 200)
 select jsonb_build_object('items',coalesce((select jsonb_agg(to_jsonb(p)||jsonb_build_object('rating_count',r.rating_count,'avg_rating',r.avg_rating,'discount_title',d.title,'discount_percent',d.percent)order by p.distance_km,p.id)
 from page p left join lateral(select count(*)rating_count,avg(rating)avg_rating from public.business_ratings where business_id=p.id)r on true
 left join lateral(select title,percent from public.business_discounts where business_id=p.id and active=true order by title,percent limit 1)d on true),'[]'::jsonb),'has_more',(select count(*)>200 from nearest))into result;
 return result;
end$$;
create or replace function public.nearby_businesses(p_lat double precision,p_lng double precision,p_radius double precision)returns jsonb language sql security invoker set search_path='' as $$select app_private.nearby_businesses(p_lat,p_lng,p_radius)$$;
revoke all on function public.nearby_businesses(double precision,double precision,double precision),app_private.nearby_businesses(double precision,double precision,double precision)from public,anon;
grant execute on function public.nearby_businesses(double precision,double precision,double precision),app_private.nearby_businesses(double precision,double precision,double precision)to authenticated;
notify pgrst,'reload schema';
