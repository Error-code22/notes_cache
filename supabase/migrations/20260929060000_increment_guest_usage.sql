-- ============================================================
-- Atomic guest usage counter - 2026-09-29 (cost control, part 2)
--
-- Notesy cannot bump a column with PostgREST (PATCH values must be
-- literals, so `text_count = text_count + 1` is not expressible), and a
-- read-modify-write from the edge function would race under the exact
-- load this table exists to stop. So the reset-if-stale + increment pair
-- happens here in one statement.
--
-- SECURITY DEFINER because the caller (notesy) connects as service_role,
-- which is already able to write the table anyway - the important part is
-- that EXECUTE is not handed to anon, so a client cannot poke the counter
-- directly. Grants are narrowed to service_role at the end.
-- ============================================================

create or replace function public.increment_guest_ai_usage(p_hash text, p_field text)
returns void
language sql
security definer
set search_path = public
as $$
  insert into public.guest_ai_usage (ip_hash, last_reset)
  values (p_hash, now())
  on conflict (ip_hash) do nothing;

  -- Every expression below reads the OLD row, so last_reset is still the
  -- stale value while the counts are being decided: they reset together.
  update public.guest_ai_usage
  set last_reset  = case when last_reset < now() - interval '24 hours' then now() else last_reset end,
      text_count  = (case when last_reset < now() - interval '24 hours' then 0 else text_count end)
                    + case when p_field = 'text_count'  then 1 else 0 end,
      image_count = (case when last_reset < now() - interval '24 hours' then 0 else image_count end)
                    + case when p_field = 'image_count' then 1 else 0 end
  where ip_hash = p_hash;
$$;

comment on function public.increment_guest_ai_usage(text, text) is
  'Resets guest counters once per 24h window and increments p_field.';

revoke execute on function public.increment_guest_ai_usage(text, text) from public;
revoke execute on function public.increment_guest_ai_usage(text, text) from anon;
revoke execute on function public.increment_guest_ai_usage(text, text) from authenticated;
grant execute on function public.increment_guest_ai_usage(text, text) to service_role;
