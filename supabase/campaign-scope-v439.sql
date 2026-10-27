create or replace function app_private.publish_campaign_batch_v439(p_data jsonb,p_client_id uuid)returns jsonb language plpgsql security definer set search_path=''as $$
declare actor text:=app_private.verified_phone();saved app_private.campaign_batches_v439%rowtype;t jsonb;ds text[];c text;n text;r jsonb;ids jsonb:='[]';idx integer:=0;begin
 if length(trim(coalesce(p_data->>'title','')))not between 1 and 160 or length(trim(coalesce(p_data->>'body','')))not between 1 and 5000 then raise exception 'შეავსე სათაური და ტექსტი.';end if;
 if p_client_id is null or jsonb_typeof(p_data->'audience')is distinct from 'array'or jsonb_array_length(p_data->'audience')not between 1 and 256 then raise exception 'აირჩიე გავრცელების ადგილები.';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_client_id::text,439));select *into saved from app_private.campaign_batches_v439 where id=p_client_id;
 if found then if saved.actor<>actor or saved.payload<>p_data then raise exception 'Request conflict'using errcode='42501';end if;return saved.result;end if;
 -- Validate the whole batch before publishing any segment.
 for t in select value from jsonb_array_elements(p_data->'audience')loop
 c:=t->>'city';n:=nullif(t->>'neighborhood','');select array_agg(distinct value)into ds from jsonb_array_elements_text(t->'districts');
 if coalesce(cardinality(ds),0)=0 or exists(select 1 from unnest(ds)d where not exists(select 1 from app_private.location_catalog l where l.city=c and l.district=d and(n is null or l.neighborhoods?n)))or(n is not null and cardinality(ds)<>1)then raise exception 'Invalid audience';end if;
 if not app_private.staff_can_v433('campaigns',c,ds)then raise exception 'ამ არეალში გამოქვეყნების უფლება არ გაქვს.'using errcode='42501';end if;
 end loop;
 insert into app_private.campaign_batches_v439(id,actor,payload)values(p_client_id,actor,p_data);
 for t in select value from jsonb_array_elements(p_data->'audience')loop
 idx:=idx+1;r:=app_private.publish_staff_campaign_v433((p_data-'audience')||t,md5(p_client_id::text||':'||idx)::uuid);ids:=ids||jsonb_build_array(r->>'id');
 end loop;
 r:=jsonb_build_object('ok',true,'ids',ids);update app_private.campaign_batches_v439 set result=r where id=p_client_id;return r;end$$;
