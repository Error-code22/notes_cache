-- Push webhook hardening.
--
-- The chat push trigger must authenticate to the send-push Edge Function,
-- but Postgres has no access to the Supabase service-role key (no
-- app.settings.* GUCs exist). Instead the DATABASE generates its own random
-- secret; the trigger sends it, and the Edge Function verifies it by reading
-- the same row back with its service-role client. The secret never appears
-- in git, in edge-function env vars, or in any client bundle.
--
-- RLS is enabled with NO policies, so only the service role (and the
-- SECURITY DEFINER trigger function) can read it.

CREATE EXTENSION IF NOT EXISTS pg_net;

CREATE TABLE IF NOT EXISTS push_webhook_secrets (
  id        smallint PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  secret    text NOT NULL DEFAULT md5(gen_random_uuid()::text || clock_timestamp()::text || random()::text),
  created_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO push_webhook_secrets (id) VALUES (1) ON CONFLICT DO NOTHING;
ALTER TABLE push_webhook_secrets ENABLE ROW LEVEL SECURITY;

-- Dedupe: one push per chat message even if trigger + client both fire.
CREATE TABLE IF NOT EXISTS push_sent (
  key     text PRIMARY KEY,
  sent_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE push_sent ENABLE ROW LEVEL SECURITY;

-- Replaces the 20260921010000 version, whose Authorization header read a
-- GUC that does not exist on this project.
CREATE OR REPLACE FUNCTION public.notify_chat_message()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  payload json;
BEGIN
  payload := json_build_object(
    'type', 'INSERT',
    'table', 'chat_messages',
    'record', to_jsonb(NEW)
  );

  PERFORM net.http_post(
    url := 'https://wgxsumbvhzwljxyozdsd.supabase.co/functions/v1/send-push',
    body := payload::jsonb,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || (SELECT secret FROM push_webhook_secrets LIMIT 1)
    ),
    timeout_milliseconds := 10000
  );

  RETURN NEW;
END;
$$;
