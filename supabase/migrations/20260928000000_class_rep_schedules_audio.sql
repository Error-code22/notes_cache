-- Class rep role, auto-approved rep donations, class schedule + server
-- push alerts, and audio-AI provider config.

-- ════════════════════════════════════════════════════════════════════
-- 1) Class rep helper
--    Flutter stores roles as enum names ('classRep', comma-joined);
--    the web admin may store 'class_rep'. Match both (ILIKE = case-insensitive).
-- ════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.is_class_rep()
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM profiles
    WHERE profiles.id = auth.uid()
      AND (profiles.role ILIKE '%class_rep%' OR profiles.role ILIKE '%classrep%')
  )
$$;

-- ════════════════════════════════════════════════════════════════════
-- 2) Donation publishing split: approve_donation keeps the admin gate,
--    publish_donation is the bare copy-into-library step so a trigger
--    can run it for class reps without them being admins.
--    publish_donation is not executable by clients (revoke below) —
--    only approve_donation (admin-gated) and the trigger may call it.
-- ════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.publish_donation(p_id BIGINT)
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  d RECORD;
  note_id TEXT;
BEGIN
  SELECT * INTO d FROM donated_notes WHERE id = p_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'donation % not found', p_id;
  END IF;
  IF d.status = 'approved' THEN
    RETURN d.library_note_id; -- idempotent
  END IF;

  INSERT INTO notes (
    title, lecturer_name, target_year, semester, gdrive_id, content,
    category, file_size, user_id, pdf_url, telegram_msg_id, telegram_file_id
  ) VALUES (
    d.title, 'Student Donation', d.target_year, d.semester, d.gdrive_id, d.content,
    COALESCE(d.category, 'Donation'), COALESCE(d.file_size, 0), d.user_id,
    d.pdf_url, d.telegram_msg_id, d.telegram_file_id
  )
  RETURNING id INTO note_id;

  UPDATE donated_notes
  SET status = 'approved', reviewed_at = NOW(), reviewed_by = auth.uid(),
      review_note = NULL, library_note_id = note_id
  WHERE id = p_id;

  RETURN note_id;
END;
$$;

-- Clients must not call the ungated publisher directly.
REVOKE EXECUTE ON FUNCTION public.publish_donation(BIGINT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.publish_donation(BIGINT) FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.approve_donation(p_id BIGINT)
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'admins only';
  END IF;
  RETURN public.publish_donation(p_id);
END;
$$;

-- ════════════════════════════════════════════════════════════════════
-- 3) Auto-approve: a class rep's own donation is published immediately
--    (fires AFTER INSERT; guests/students still queue for review).
-- ════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.auto_approve_rep_donation()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NEW.status = 'pending' AND public.is_class_rep() THEN
    PERFORM public.publish_donation(NEW.id);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_auto_approve_rep_donation ON donated_notes;
CREATE TRIGGER trg_auto_approve_rep_donation
AFTER INSERT ON donated_notes
FOR EACH ROW
EXECUTE FUNCTION public.auto_approve_rep_donation();

-- ════════════════════════════════════════════════════════════════════
-- 4) Class schedule — reps set "next class" times; everyone can read,
--    only class reps (or admins) can write.
--    target_year NULL = alert every user; N = only that year.
-- ════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS class_schedules (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_by UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  location TEXT,
  class_time TIMESTAMPTZ NOT NULL,
  notify_minutes_before INT NOT NULL DEFAULT 15,
  repeat_weekly BOOLEAN NOT NULL DEFAULT FALSE,
  target_year INT,
  notified_at TIMESTAMPTZ,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_class_schedules_due
  ON class_schedules(class_time) WHERE notified_at IS NULL;

ALTER TABLE class_schedules ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated read schedules" ON class_schedules
  FOR SELECT USING (auth.role() = 'authenticated');

CREATE POLICY "Reps insert schedules" ON class_schedules
  FOR INSERT WITH CHECK (
    created_by = auth.uid() AND (public.is_class_rep() OR public.is_admin())
  );

CREATE POLICY "Reps update own schedules" ON class_schedules
  FOR UPDATE USING (created_by = auth.uid() OR public.is_admin())
  WITH CHECK (created_by = auth.uid() OR public.is_admin());

CREATE POLICY "Reps delete own schedules" ON class_schedules
  FOR DELETE USING (created_by = auth.uid() OR public.is_admin());

-- ════════════════════════════════════════════════════════════════════
-- 5) Alert dispatcher — runs every minute via pg_cron (same machinery
--    as the keepalive job). Claims the row first (rollback-safe: if the
--    HTTP queueing fails, notified_at is undone and we retry next tick),
--    then POSTs to send-push authenticated with the DB webhook secret.
-- ════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.dispatch_class_alerts()
RETURNS INTEGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  s RECORD;
  sent INTEGER := 0;
  body JSONB;
BEGIN
  FOR s IN
    SELECT * FROM class_schedules
    WHERE notified_at IS NULL
      AND class_time - (notify_minutes_before || ' minutes')::interval <= NOW()
      -- never fire for classes that already ended >1h ago (missed window)
      AND class_time > NOW() - INTERVAL '1 hour'
    ORDER BY class_time
  LOOP
    -- claim before sending (same transaction: all-or-nothing)
    UPDATE class_schedules SET notified_at = NOW() WHERE id = s.id;

    IF s.target_year IS NULL THEN
      body := jsonb_build_object('all', true);
    ELSE
      body := jsonb_build_object('year', s.target_year);
    END IF;
    body := body || jsonb_build_object(
      'title', 'Class starting soon',
      'body', s.title
        || ' starts in ' || s.notify_minutes_before || ' min'
        || COALESCE(' — ' || s.location, ''),
      'data', jsonb_build_object('kind', 'class_schedule', 'id', s.id::text)
    );

    PERFORM net.http_post(
      url := 'https://wgxsumbvhzwljxyozdsd.supabase.co/functions/v1/send-push',
      body := body,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || (SELECT secret FROM push_webhook_secrets LIMIT 1)
      ),
      timeout_milliseconds := 10000
    );

    IF s.repeat_weekly THEN
      UPDATE class_schedules
      SET class_time = class_time + INTERVAL '7 days', notified_at = NULL
      WHERE id = s.id;
    END IF;

    sent := sent + 1;
  END LOOP;
  RETURN sent;
END;
$$;

-- Every minute, same pattern as keepalive-ping (safe to re-run: replaces by name)
SELECT cron.schedule(
  'class-alert-dispatch',
  '* * * * *',
  $$SELECT public.dispatch_class_alerts();$$
);

-- ════════════════════════════════════════════════════════════════════
-- 6) Audio AI config + daily usage bucket
-- ════════════════════════════════════════════════════════════════════
INSERT INTO app_config (key, value) VALUES
  ('ai_audio_provider', 'gemini'),
  ('ai_audio_model', 'gemini-3.5-transcribe'),
  ('ai_audio_fallback_provider', 'groq'),
  ('ai_audio_fallback_model', 'whisper-large-v3-turbo'),
  ('ai_audio_events', 'true'),
  ('ai_daily_audio_limit', '10')
ON CONFLICT (key) DO NOTHING;

ALTER TABLE user_ai_usage ADD COLUMN IF NOT EXISTS audio_count INT DEFAULT 0;

CREATE OR REPLACE FUNCTION increment_ai_usage(user_id_param UUID, field_name TEXT)
RETURNS VOID AS $$
BEGIN
    IF field_name = 'text_count' THEN
        UPDATE user_ai_usage SET text_count = text_count + 1 WHERE user_id = user_id_param;
    ELSIF field_name = 'image_count' THEN
        UPDATE user_ai_usage SET image_count = image_count + 1 WHERE user_id = user_id_param;
    ELSIF field_name = 'audio_count' THEN
        UPDATE user_ai_usage SET audio_count = audio_count + 1 WHERE user_id = user_id_param;
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
