-- Repair: list_donation_queue was pushed before its admin guard landed in
-- the file, so the deployed version leaks every donation to any caller.
-- Re-assert all three review functions (idempotent) and prove it with a
-- rolled-back end-to-end test (see the probe run for this migration).

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

-- Re-stamp the guards (no behaviour change if already correct).
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
