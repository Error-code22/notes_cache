-- ============================================================
-- Recall fix: OR the query terms instead of ANDing them - 2026-09-29 (part 5)
--
-- The function used plainto_tsquery(), which ANDs every word in the input.
-- That is fine for keyword search and useless for how students actually
-- ask: "How does indexing work in a database? Explain B-tree indexes."
-- returned zero rows, so RAG silently injected an empty context and the
-- model answered from general knowledge while the UI claimed otherwise.
-- Measured before the fix:  'database' -> 5 hits, 'indexing database' -> 3,
-- but the full question -> 0.
--
-- websearch_to_tsquery() takes untrusted input safely (it sanitises
-- metacharacters), and joining the extracted words with OR is what we
-- want. The english dictionary still drops stopwords and stems both
-- sides, so 'indexing' matches 'index'. Precision comes from ts_rank
-- ordering plus the rank floor and per-source diversification in notesy
-- rather than from requiring every word to co-occur.
--
-- DROP + CREATE resets grants, so they are repeated verbatim below.
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
  terms AS (
    -- Split on anything that is not a letter or digit, so punctuation and
    -- hyphens in the question cannot reach the query parser. unnest() with
    -- an explicit column alias is required here: naming a table alias on
    -- regexp_split_to_array() leaves `t` as a whole-row reference, which
    -- string_agg() cannot read as text.
    SELECT DISTINCT t.term
    FROM unnest(regexp_split_to_array(lower(COALESCE(query_text, '')), '[^a-z0-9]+')) AS t(term)
    WHERE t.term <> ''
  ),
  q AS (
    SELECT CASE
      WHEN EXISTS (SELECT 1 FROM terms) THEN
        websearch_to_tsquery('english', (SELECT string_agg(term, ' OR ') FROM terms))
      ELSE NULL
    END AS tsq
  )
  SELECT c.id, c.note_id, c.source, c.page, c.preview, c.telegram_msg_id,
         c.created_at, c.fts, ts_rank(c.fts, q.tsq)::real AS rank
  FROM chunks c
  JOIN notes n ON n.id = c.note_id
  CROSS JOIN q
  WHERE q.tsq IS NOT NULL
    AND c.fts @@ q.tsq
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
