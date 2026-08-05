-- ============================================================
-- Download tracking + admin usage charts
-- Cloudinary's API only exposes current usage (no daily history),
-- so the app logs every note download and we chart from that.
-- ============================================================

CREATE TABLE IF NOT EXISTS downloads (
  id BIGSERIAL PRIMARY KEY,
  note_id TEXT,
  user_id UUID,
  file_size INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE downloads ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Service role manages downloads" ON downloads
  FOR ALL USING (auth.role() = 'service_role');

CREATE INDEX IF NOT EXISTS idx_downloads_created ON downloads (created_at);

-- App-side insert (SECURITY DEFINER so the anon key can log, but only writes)
CREATE OR REPLACE FUNCTION log_download(p_note_id TEXT, p_file_size INT)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO downloads (note_id, user_id, file_size)
  VALUES (p_note_id, auth.uid(), p_file_size);
END;
$$;

GRANT EXECUTE ON FUNCTION log_download(text, int) TO anon, authenticated;

-- Daily download/bandwidth buckets for the admin charts
CREATE OR REPLACE FUNCTION get_download_stats(p_days INT DEFAULT 14)
RETURNS TABLE (day DATE, downloads_count BIGINT, bandwidth_bytes BIGINT)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT created_at::date AS day, COUNT(*)::bigint, COALESCE(SUM(file_size), 0)::bigint
  FROM downloads
  WHERE created_at >= CURRENT_DATE - p_days + 1
  GROUP BY created_at::date
  ORDER BY day;
$$;

GRANT EXECUTE ON FUNCTION get_download_stats(int) TO anon, authenticated;

-- Daily upload/storage-growth buckets from the notes table
CREATE OR REPLACE FUNCTION get_storage_growth(p_days INT DEFAULT 14)
RETURNS TABLE (day DATE, uploads_count BIGINT, storage_bytes BIGINT)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT created_at::date AS day, COUNT(*)::bigint, COALESCE(SUM(file_size), 0)::bigint
  FROM notes
  WHERE created_at >= CURRENT_DATE - p_days + 1
  GROUP BY created_at::date
  ORDER BY day;
$$;

GRANT EXECUTE ON FUNCTION get_storage_growth(int) TO anon, authenticated;
