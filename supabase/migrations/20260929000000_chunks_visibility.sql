-- ============================================================
-- Chunk visibility hardening - 2026-09-29
--
-- Problem:
--   * chunks carried no link to the note it came from, so it could not
--     be filtered by the same rules that govern `notes`.
--   * policy "Chunks public read" had qual = true - every anon request
--     could read all extracted document text (verified: 1962 rows).
--   * search_chunks_fts was granted to anon AND PUBLIC.
--   * donate_notes_page indexes the file BEFORE admin approval, so
--     pending donations landed in `chunks` readable by anyone.
--
-- Fix:
--   * add chunks.note_id, backfill from source = notes.title
--   * unlinked chunks (pending donations, deleted notes) become invisible
--   * SELECT now mirrors the `notes` visibility rules
--   * drop the anon/PUBLIC EXECUTE grants on search_chunks_fts
--   * approve_donation links the chunks it just published
-- ============================================================

-- 1) Link every chunk to the note it was extracted from.
ALTER TABLE chunks
  ADD COLUMN IF NOT EXISTS note_id BIGINT REFERENCES notes(id) ON DELETE CASCADE;

UPDATE chunks c
SET note_id = n.id
FROM notes n
WHERE c.source = n.title
  AND c.note_id IS NULL;

CREATE INDEX IF NOT EXISTS idx_chunks_note_id ON chunks(note_id);

-- 2) Remove the wide-open read policy.
DROP POLICY IF EXISTS "Chunks public read" ON chunks;

-- 3) Rebuild it so a chunk is readable exactly when its note is.
--    note_id IS NOT NULL hides pending donations (indexed at donate time,
--    before a `notes` row exists) and chunks whose note was deleted.
CREATE POLICY "Chunks read by note visibility" ON chunks
  FOR SELECT USING (
    note_id IS NOT NULL
    AND EXISTS (
      SELECT 1 FROM notes n
      WHERE n.id = note_id
        AND (
          auth.role() = 'anon'
          OR EXISTS (
            SELECT 1 FROM profiles
            WHERE profiles.id = auth.uid()
              AND (profiles.role ILIKE '%admin%'
                OR profiles.role ILIKE '%lecturer%'
                OR profiles.role ILIKE '%moderator%')
          )
          OR n.target_year = (
            SELECT year_level FROM profiles WHERE id = auth.uid()
          )
        )
    )
  );

-- 4) The AI search RPC is for signed-in callers via notesy only.
--    (notesy uses service_role, which bypasses RLS, so it filters
--    explicitly in the edge function - see handleSearchLectureDocs.)
REVOKE EXECUTE ON FUNCTION public.search_chunks_fts(TEXT, INT) FROM anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.search_chunks_fts(TEXT, INT) TO authenticated, service_role;

-- 5) New chunks resolve their note_id at insert time so uploads that
--    already have a `notes` row are linked immediately. Donations have
--    no row yet, so they stay note_id = NULL until approval.
CREATE OR REPLACE FUNCTION insert_chunks(p_chunks JSONB)
RETURNS INT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  c JSONB;
  inserted INT := 0;
  linked_id BIGINT;
BEGIN
  FOR c IN SELECT * FROM jsonb_array_elements(p_chunks) LOOP
    SELECT id INTO linked_id FROM notes WHERE title = (c->>'source') LIMIT 1;

    INSERT INTO chunks (source, page, preview, note_id)
    VALUES (
      c->>'source',
      COALESCE((c->>'page')::int, 1),
      c->>'preview',
      linked_id
    );
    inserted := inserted + 1;
  END LOOP;
  RETURN inserted;
END;
$$;

CREATE OR REPLACE FUNCTION insert_chunk(p_source TEXT, p_page INT, p_preview TEXT)
RETURNS BIGINT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  new_id BIGINT;
  linked_id BIGINT;
BEGIN
  SELECT id INTO linked_id FROM notes WHERE title = p_source LIMIT 1;

  INSERT INTO chunks (source, page, preview, note_id)
  VALUES (p_source, p_page, p_preview, linked_id)
  RETURNING id INTO new_id;

  RETURN new_id;
END;
$$;

GRANT EXECUTE ON FUNCTION insert_chunks(jsonb) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION insert_chunk(text, int, text) TO anon, authenticated;

-- 6) Publishing is publish_donation (approve_donation merely gates it, and
--    the class-rep trigger calls publish_donation directly). Link the chunks
--    that were indexed while the donation was pending - otherwise the note
--    just published would stay invisible to search, because its note_id has
--    been NULL since donate_notes_page indexed it.
CREATE OR REPLACE FUNCTION public.publish_donation(p_id BIGINT)
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  d RECORD;
  new_note_id TEXT;
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
  RETURNING id INTO new_note_id;

  UPDATE chunks
  SET note_id = new_note_id::bigint
  WHERE source = d.title
    AND chunks.note_id IS NULL;

  UPDATE donated_notes
  SET status = 'approved', reviewed_at = NOW(), reviewed_by = auth.uid(),
      review_note = NULL, library_note_id = new_note_id
  WHERE id = p_id;

  RETURN new_note_id;
END;
$$;

-- Re-assert the client lockdown from 20260928 (CREATE OR REPLACE resets
-- no grants, but this keeps the file self-contained if it is ever replayed).
REVOKE EXECUTE ON FUNCTION public.publish_donation(BIGINT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.publish_donation(BIGINT) FROM anon, authenticated;
