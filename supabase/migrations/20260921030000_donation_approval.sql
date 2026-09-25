-- Donation approval flow.
--
-- Before: web /donate wrote straight into `notes` (instantly public, no
-- review) while the Flutter app wrote into `donated_notes` (never reviewed,
-- and with a file_url column that Note.fromMap doesn't read, so files didn't
-- open). Now BOTH paths write to donated_notes with status='pending', and an
-- admin approval copies the row into the shared `notes` library.

-- 1) Schema: review columns + the file columns notes has but this table lacks
ALTER TABLE donated_notes
  ADD COLUMN IF NOT EXISTS gdrive_id TEXT,
  ADD COLUMN IF NOT EXISTS pdf_url TEXT,
  ADD COLUMN IF NOT EXISTS telegram_msg_id BIGINT,
  ADD COLUMN IF NOT EXISTS telegram_file_id TEXT,
  ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'pending',
  ADD COLUMN IF NOT EXISTS review_note TEXT,
  ADD COLUMN IF NOT EXISTS reviewed_at TIMESTAMP WITH TIME ZONE,
  ADD COLUMN IF NOT EXISTS reviewed_by UUID;

DO $$ BEGIN
  ALTER TABLE donated_notes ADD CONSTRAINT donated_notes_status_check
    CHECK (status IN ('pending', 'approved', 'rejected'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- 2) Backfill: rows created before the gate existed stay visible; older
--    Flutter rows stored the file URL in file_url only.
UPDATE donated_notes SET gdrive_id = file_url WHERE gdrive_id IS NULL AND file_url IS NOT NULL;
UPDATE donated_notes SET status = 'approved' WHERE status = 'pending';

CREATE INDEX IF NOT EXISTS idx_donated_notes_status ON donated_notes(status, created_at DESC);

-- 3) Helpers
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM profiles
    WHERE profiles.id = auth.uid() AND profiles.role ILIKE '%admin%'
  )
$$;

-- 4) RLS: approved is public to signed-in users; your own submissions are
--    always visible to you; only admins see everyone's pending/rejected.
DROP POLICY IF EXISTS "Authenticated read donated notes" ON donated_notes;
CREATE POLICY "Read approved or own donations" ON donated_notes
  FOR SELECT USING (
    status = 'approved'
    OR user_id = auth.uid()
    OR public.is_admin()
  );

DROP POLICY IF EXISTS "Admins review donations" ON donated_notes;
CREATE POLICY "Admins review donations" ON donated_notes
  FOR UPDATE USING (public.is_admin()) WITH CHECK (public.is_admin());

-- 5) Approval: copy into the shared library, then mark reviewed.
--    SECURITY DEFINER so the donor never needs INSERT rights on `notes`
--    (guest donations have user_id NULL and would fail RLS otherwise).
CREATE OR REPLACE FUNCTION public.approve_donation(p_id BIGINT)
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  d RECORD;
  note_id TEXT;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'admins only';
  END IF;

  SELECT * INTO d FROM donated_notes WHERE id = p_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'donation % not found', p_id;
  END IF;
  IF d.status = 'approved' THEN
    RETURN NULL; -- idempotent: already in the library
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
  SET status = 'approved', reviewed_at = NOW(), reviewed_by = auth.uid(), review_note = NULL
  WHERE id = p_id;

  RETURN note_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.reject_donation(p_id BIGINT, p_note TEXT DEFAULT NULL)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'admins only';
  END IF;
  UPDATE donated_notes
  SET status = 'rejected', reviewed_at = NOW(), reviewed_by = auth.uid(), review_note = p_note
  WHERE id = p_id AND status <> 'approved';
END;
$$;

-- 6) Admin listing: pending queue + counts in one call (admins only)
CREATE OR REPLACE FUNCTION public.list_donation_queue(p_status TEXT DEFAULT 'pending')
RETURNS SETOF donated_notes LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RETURN; -- non-admins get an empty queue, not an error
  END IF;
  RETURN QUERY
    SELECT * FROM donated_notes
    WHERE status = p_status
    ORDER BY created_at DESC
    LIMIT 200;
END;
$$;
