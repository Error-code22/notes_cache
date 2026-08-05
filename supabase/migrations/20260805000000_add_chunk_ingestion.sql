-- ============================================================
-- AI chunk ingestion for Notesy RAG
-- Makes the chunks table + search function reproducible and
-- adds insert_chunk, a SECURITY DEFINER RPC so the app's anon
-- key can add new document chunks without direct table access.
-- ============================================================

-- ── chunks table ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS chunks (
  id BIGSERIAL PRIMARY KEY,
  source TEXT NOT NULL,
  page INT NOT NULL DEFAULT 1,
  preview TEXT NOT NULL,
  telegram_msg_id INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  fts TSVECTOR GENERATED ALWAYS AS (to_tsvector('english', preview)) STORED
);

CREATE INDEX IF NOT EXISTS idx_chunks_fts ON chunks USING GIN (fts);
CREATE INDEX IF NOT EXISTS idx_chunks_source ON chunks (source);

-- ── search function used by Notesy ──────────────────────────
-- Drop first: the original was created with telegram_msg_id INT;
-- replacing with a different return type errors (42P13).
DROP FUNCTION IF EXISTS search_chunks_fts(text, integer);
CREATE FUNCTION search_chunks_fts(query_text TEXT, match_limit INT DEFAULT 3)
RETURNS TABLE (id BIGINT, source TEXT, page INT, preview TEXT, telegram_msg_id INT, created_at TIMESTAMPTZ, fts TSVECTOR)
LANGUAGE sql STABLE AS $$
  SELECT id, source, page, preview, telegram_msg_id, created_at, fts
  FROM chunks
  WHERE fts @@ plainto_tsquery('english', query_text)
  ORDER BY ts_rank(fts, plainto_tsquery('english', query_text)) DESC
  LIMIT match_limit;
$$;

-- ── safe app-side insert ────────────────────────────────────
-- SECURITY DEFINER: runs with owner privileges, bypassing RLS,
-- but only exposes a narrow insert — callers can't read or
-- modify anything else on the table.
CREATE OR REPLACE FUNCTION insert_chunk(p_source TEXT, p_page INT, p_preview TEXT)
RETURNS BIGINT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE new_id BIGINT;
BEGIN
  INSERT INTO chunks (source, page, preview)
  VALUES (p_source, p_page, p_preview)
  RETURNING id INTO new_id;
  RETURN new_id;
END;
$$;

GRANT EXECUTE ON FUNCTION insert_chunk(text, int, text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION search_chunks_fts(text, int) TO anon, authenticated;

-- Batched variant so a whole document uploads in one round trip:
-- p_chunks = [{"source": "...", "page": 1, "preview": "..."}, ...]
CREATE OR REPLACE FUNCTION insert_chunks(p_chunks JSONB)
RETURNS INT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  c JSONB;
  inserted INT := 0;
BEGIN
  FOR c IN SELECT * FROM jsonb_array_elements(p_chunks) LOOP
    INSERT INTO chunks (source, page, preview)
    VALUES (c->>'source', COALESCE((c->>'page')::int, 1), c->>'preview');
    inserted := inserted + 1;
  END LOOP;
  RETURN inserted;
END;
$$;

GRANT EXECUTE ON FUNCTION insert_chunks(jsonb) TO anon, authenticated;
