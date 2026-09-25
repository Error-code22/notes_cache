-- Fire a server push whenever a chat message is inserted.
-- Uses pg_net to POST to the send-push Edge Function, which resolves the
-- recipient's FCM tokens and delivers the notification — works even when
-- the receiving app is killed.

CREATE EXTENSION IF NOT EXISTS pg_net;

-- Function URL is stable per project+function name
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
    body := payload,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key', true)
    ),
    timeout_milliseconds := 10000
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_chat_message_push ON public.chat_messages;
CREATE TRIGGER trg_chat_message_push
  AFTER INSERT ON public.chat_messages
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_chat_message();
