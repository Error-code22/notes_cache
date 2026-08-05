-- ============================================================
-- 24/7 keep-alive so the free-tier project never pauses.
-- pg_cron fires net.http_get at the keepalive edge function
-- every 5 minutes, generating real API activity around the clock
-- without any external uptime monitor.
-- ============================================================

CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net;

-- Named schedule: safe to re-run (upserts by job name)
SELECT cron.schedule(
  'keepalive-ping',
  '*/5 * * * *',
  $$SELECT net.http_get('https://wgxsumbvhzwljxyozdsd.supabase.co/functions/v1/keepalive');$$
);
