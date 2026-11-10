-- Allow an invitee to change or withdraw a response while the hosting is still recruiting and before it starts.
-- Previously only the first response from 'pending' was accepted, so the iOS change/withdraw actions returned 409.
-- The public wrapper from 202610300001_automatic_scheduling.sql keeps calling this inner function;
-- create or replace keeps the existing (revoked) privileges of the inner function.

create or replace function public.hosting_respond_before_scheduling(
  p_hosting_id uuid,p_status text,p_intervals jsonb,p_operation_id uuid,p_expected_version integer
)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare actor uuid := private.hosting_actor(); h public.hostings%rowtype; inv public.hosting_invitations%rowtype;
  payload jsonb; prior_payload jsonb; prior_hosting uuid; item jsonb; a timestamptz; b timestamptz; previous_end timestamptz;
begin
  if p_hosting_id is null or p_operation_id is null or p_expected_version is null or p_expected_version<1
     or p_status is null or p_status not in ('accepted','declined') or p_intervals is null or jsonb_typeof(p_intervals)<>'array' then
    raise exception using errcode='23514',message='hosting_unavailable';
  end if;
  payload:=jsonb_build_object('hostingId',p_hosting_id,'status',p_status,'intervals',p_intervals,'expectedVersion',p_expected_version);
  perform pg_advisory_xact_lock(hashtextextended(actor::text||':hosting:'||p_operation_id::text,0));
  select o.payload,o.hosting_id into prior_payload,prior_hosting from private.hosting_operations o
    where o.actor_user_id=actor and o.operation_id=p_operation_id;
  if found then
    if prior_payload<>payload or (select operation_kind from private.hosting_operations where actor_user_id=actor and operation_id=p_operation_id)<>'respond' then
      raise exception using errcode='23505',message='hosting_conflict';
    end if;
    return private.hosting_projection(actor,prior_hosting);
  end if;
  select * into h from public.hostings where id=p_hosting_id for update;
  if h.id is null or h.host_user_id=actor or h.status<>'recruiting' or h.start_at<=now() then
    raise exception using errcode='P0002',message='hosting_unavailable';
  end if;
  select * into inv from public.hosting_invitations where hosting_id=p_hosting_id and invitee_user_id=actor for update;
  if inv.hosting_id is null then raise exception using errcode='P0002',message='hosting_unavailable'; end if;
  -- An invitee may change the accepted time or withdraw while the hosting is open (ios-hosting 3.4).
  -- Optimistic concurrency still rejects any stale version.
  if inv.version<>p_expected_version then raise exception using errcode='40001',message='hosting_conflict'; end if;
  if (p_status='accepted' and jsonb_array_length(p_intervals)=0) or (p_status='declined' and jsonb_array_length(p_intervals)<>0) then
    raise exception using errcode='23514',message='hosting_unavailable';
  end if;
  for item in select value from jsonb_array_elements(p_intervals) with ordinality as intervals(value,ordinality) order by ordinality loop
    begin a:=(item->>'start')::timestamptz; b:=(item->>'end')::timestamptz;
    exception when others then raise exception using errcode='23514',message='hosting_unavailable'; end;
    if jsonb_typeof(item)<>'object' or a is null or b is null or a>=b or a<h.start_at or b>h.end_at
      or extract(epoch from a) - floor(extract(epoch from a) / 900) * 900 <> 0
      or extract(epoch from b) - floor(extract(epoch from b) / 900) * 900 <> 0 then
      raise exception using errcode='23514',message='hosting_unavailable';
    end if;
    if previous_end is not null and a<previous_end then raise exception using errcode='23514',message='hosting_unavailable'; end if;
    previous_end:=b;
  end loop;
  update public.hosting_invitations set status=p_status,intervals=p_intervals,version=version+1,last_operation_id=p_operation_id
    where hosting_id=p_hosting_id and invitee_user_id=actor;
  insert into private.hosting_operations(actor_user_id,operation_id,operation_kind,payload,hosting_id)
    values(actor,p_operation_id,'respond',payload,p_hosting_id);
  return private.hosting_projection(actor,p_hosting_id);
end; $$;
