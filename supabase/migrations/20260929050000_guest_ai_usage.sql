-- ============================================================
-- Guest AI usage - 2026-09-29 (cost control)
--
-- Signed-in users are capped by user_ai_usage, but guests were not:
-- validateJwt() hands back the 'guest_user' sentinel, notesy skipped the
-- usage block entirely, and the only limit was in the Flutter client.
-- Anyone with the anon key could call the function in a loop and burn the
-- Groq/Gemini quota with no account to ban.
--
-- Keyed by a salted hash of the caller IP rather than the raw address,
-- so we can throttle without keeping a log of where requests came from.
--
-- No policies at all = default deny. anon/authenticated cannot read or
-- write it; only service_role (which is how notesy connects) can.
-- ============================================================

create table if not exists public.guest_ai_usage (
  ip_hash text primary key,
  text_count int not null default 0,
  image_count int not null default 0,
  last_reset timestamptz not null default now()
);

comment on table public.guest_ai_usage is
  'Per-IP daily AI usage for unauthenticated Notesy callers. ip_hash is SHA-256(ip + server salt), not a raw address.';

-- Belt and braces: even if a policy is added later by mistake, the
-- client-facing roles get nothing.
revoke all on table public.guest_ai_usage from anon;
revoke all on table public.guest_ai_usage from authenticated;

-- Migration bookkeeping only; not user data.
insert into public.app_config (key, value)
values ('ai_guest_daily_text_limit', '15'),
       ('ai_guest_daily_image_limit', '5')
on conflict (key) do nothing;
