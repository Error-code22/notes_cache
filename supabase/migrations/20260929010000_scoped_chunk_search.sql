-- ============================================================
-- Scoped chunk search - 2026-09-29 (part 2 of chunks hardening)
--
-- Why this cannot rely on RLS:
--   notesy runs as service_role, which BYPASSES row level security.
--   The visibility rules therefore have to be enforced inside the
--   function itself, or the AI reads everything regardless of the
--   policy added in 20260929000000_chunks_visibility.sql.
--
-- Also fixes a spoofing hole: if the function accepted p_user_id
-- from any caller, an authenticated user could pass an admin's uuid
-- and inherit staff visibility. auth.uid() always wins when present,
-- so only service_role (which has no auth.uid()) supplies the id.
--
-- Only notesy calls this (verified: no app/web callers), so the
-- authenticated grant is dropped - least privilege.
-- ============================================================

DROP FUNCTION IF EXISTS public.search_chunks_fts(TEXT, INT);

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
  fts TSVECTOR
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
  )
  SELECT c.id, c.source, c.page, c.preview, c.telegram_msg_id, c.created_at, c.fts
  FROM chunks c
  JOIN notes n ON n.id = c.note_id
  WHERE c.fts @@ plainto_tsquery('english', query_text)
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
  ORDER BY ts_rank(c.fts, plainto_tsquery('english', query_text)) DESC
  LIMIT match_limit;
$$;

-- notesy is the sole caller and authenticates with service_role.
-- Anyone else is turned away at the grant layer before RLS matters.
REVOKE EXECUTE ON FUNCTION public.search_chunks_fts(TEXT, INT, UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.search_chunks_fts(TEXT, INT, UUID) FROM anon;
REVOKE EXECUTE ON FUNCTION public.search_chunks_fts(TEXT, INT, UUID) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.search_chunks_fts(TEXT, INT, UUID) TO service_role;
