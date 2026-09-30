-- ============================================================
-- Ranked chunk search - 2026-09-29 (part 3 of chunks hardening)
--
-- The previous version ordered by ts_rank but threw the rank away, so
-- callers could not tell a strong match from the least-bad match. That
-- matters for Notesy: with no floor, a query that only half-matches still
-- returns N rows, and the model happily grounds an answer in them.
--
-- Adding a column to the return type means DROP + CREATE (Postgres
-- refuses to change a function's signature in place), which also drops
-- every grant - so the revokes/grants from the part-2 migration are
-- repeated verbatim here.
-- ============================================================

DROP FUNCTION IF EXISTS public.search_chunks_fts(TEXT, INT, UUID);

CREATE FUNCTION public.search_chunks_fts(
  query_text TEXT,
  match_limit INT DEFAULT 3,
  p_user_id UUID DEFAULT NULL
)
RETURNS TABLE (
  id BIGINT,
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
  SELECT c.id, c.source, c.page, c.preview, c.telegram_msg_id, c.created_at,
         c.fts, ts_rank(c.fts, q.tsq)::real AS rank
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
