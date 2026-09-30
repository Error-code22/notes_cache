-- ============================================================
-- Expose note_id from chunk search - 2026-09-29 (part 4)
--
-- Notesy resolved chunk.source -> notes.id by matching titles, which is
-- fragile (two notes can share a title) and cost an extra query per
-- search. Returning note_id directly lets the caller go straight to the
-- note, and lets the chat's citation chips deep-link into the note page.
--
-- Signature changes again, so DROP + CREATE - which resets the grants.
-- They are repeated verbatim below.
-- ============================================================

DROP FUNCTION IF EXISTS public.search_chunks_fts(TEXT, INT, UUID);

CREATE FUNCTION public.search_chunks_fts(
  query_text TEXT,
  match_limit INT DEFAULT 3,
  p_user_id UUID DEFAULT NULL
)
RETURNS TABLE (
  id BIGINT,
  note_id BIGINT,
  source TEXT,
  page INT,
  preview TEXT,
  telegram_msg_id INT,
  created_at TIMESTAMPTZ,
  fts TSVECTOR,
  rank REAL
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH viewer AS (
    -- auth.uid() always wins: a logged-in caller cannot impersonate
    -- anyone else by passing a different p_user_id.
    SELECT COALESCE(auth.uid(), p_user_id) AS uid
  ),
  q AS (
    SELECT plainto_tsquery('english', query_text) AS tsq
  )
  SELECT c.id, c.note_id, c.source, c.page, c.preview, c.telegram_msg_id,
         c.created_at, c.fts, ts_rank(c.fts, q.tsq)::real AS rank
  FROM chunks c
  JOIN notes n ON n.id = c.note_id
  CROSS JOIN q
  WHERE c.fts @@ q.tsq
    AND (
      -- Unauthenticated caller (service_role + guest): mirrors the
      -- "Guests read all notes" policy, but ONLY for chunks that are
      -- linked to a note - pending donations stay unreachable because
      -- they have no note_id until publish_donation links them.
      (SELECT uid FROM viewer) IS NULL
      OR EXISTS (
        SELECT 1 FROM profiles p
        WHERE p.id = (SELECT uid FROM viewer)
          AND (p.role ILIKE '%admin%'
            OR p.role ILIKE '%lecturer%'
            OR p.role ILIKE '%moderator%')
      )
      OR EXISTS (
        SELECT 1 FROM profiles p
        WHERE p.id = (SELECT uid FROM viewer)
          AND p.year_level = n.target_year
      )
    )
  ORDER BY rank DESC
  LIMIT match_limit;
$$;

-- notesy is the sole caller and authenticates with service_role.
-- Anyone else is turned away at the grant layer before RLS matters.
REVOKE EXECUTE ON FUNCTION public.search_chunks_fts(TEXT, INT, UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.search_chunks_fts(TEXT, INT, UUID) FROM anon;
REVOKE EXECUTE ON FUNCTION public.search_chunks_fts(TEXT, INT, UUID) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.search_chunks_fts(TEXT, INT, UUID) TO service_role;
