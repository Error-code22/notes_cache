-- Link an approved donation back to the row it created in `notes`.
-- The web /donate browse list needs the library id to link to /note?id=...

ALTER TABLE donated_notes ADD COLUMN IF NOT EXISTS library_note_id TEXT;

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
