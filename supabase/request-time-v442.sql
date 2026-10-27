-- Initial requests need description/address, not an appointment. Offers still require a future appointment.
-- Requires workflow-v441 already installed. No data deletion or permission changes.
create or replace function app_private.create_service_order_v432(p_ad_id uuid,p_description text,p_address text,p_from timestamptz,p_to timestamptz,p_client_id uuid)returns jsonb language plpgsql security definer set search_path=''as $$
declare actor text:=app_private.verified_phone();ad public.specialist_announcements%rowtype;me public.profiles%rowtype;oid uuid;chat jsonb;begin
 if p_client_id is null then raise exception 'Request ID required';end if;perform pg_advisory_xact_lock(hashtext(actor),hashtext(p_client_id::text));
 select id into oid from public.service_orders where customer_phone=actor and client_request_id=p_client_id;if found then return jsonb_build_object('ok',true,'id',oid);end if;
 select * into ad from public.specialist_announcements where id=p_ad_id and status='approved';select * into me from public.profiles where phone=actor;
 if ad.id is null or ad.owner_phone=actor or public.is_user_blocked(actor,ad.owner_phone)then raise exception 'Specialist unavailable'using errcode='42501';end if;
 if not(coalesce(me.is_super_admin,false)or coalesce(me.admin_level='super',false))and(ad.city is distinct from me.city or not me.district=any(ad.target_districts))then raise exception 'Specialist outside selected area'using errcode='42501';end if;
 if length(trim(coalesce(p_description,'')))not between 3 and 3000 or length(trim(coalesce(p_address,'')))not between 3 and 500 then raise exception 'აღწერე სამუშაო და მიუთითე მისამართი.';end if;
 if app_private.has_external_contact_v432(p_description)then raise exception 'კომუნიკაციისთვის გამოიყენე აპის ჩათი; ნომერი ან გარე ბმული არ მიუთითო.';end if;
 if p_from is not null or p_to is not null then perform app_private.assert_arrival_v432(p_from,p_to);end if;chat:=public.start_direct_chat(actor,ad.owner_phone);
 if chat->>'ok'<>'true' or chat->>'id'is null then raise exception 'ჩათი ვერ გაიხსნა: %',coalesce(chat->>'message','შეამოწმე მიმოწერის პარამეტრები');end if;
 insert into public.service_orders(customer_phone,provider_phone,provider_name,category,description,address,requested_time,starting_price,status,workflow_version,client_request_id,thread_id,arrival_from,arrival_to)
 values(actor,ad.owner_phone,ad.owner_name,ad.title,trim(p_description),trim(p_address),p_from,ad.price,'consultation_requested',2,p_client_id,(chat->>'id')::uuid,p_from,p_to)returning id into oid;
 -- The order is the durable context; no automatic private message is sent on behalf of the customer.
 return jsonb_build_object('ok',true,'id',oid);end$$;
