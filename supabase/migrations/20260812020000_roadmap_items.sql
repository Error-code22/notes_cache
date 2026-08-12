-- ============================================================
-- ROADMAP ITEMS — 2026-08-12
-- "Plans" = the app's upcoming-features roadmap shown on the
-- homepage bottom card (NOT pricing). Admins manage from admin dash.
-- ============================================================

CREATE TABLE IF NOT EXISTS roadmap_items (
  id BIGSERIAL PRIMARY KEY,
  title TEXT NOT NULL,
  description TEXT DEFAULT '',
  icon TEXT DEFAULT 'construction',
  sort_order INT NOT NULL DEFAULT 0,
  active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE roadmap_items ENABLE ROW LEVEL SECURITY;

-- Everyone can read the roadmap (it's on the homepage)
CREATE POLICY "Public read roadmap" ON roadmap_items
  FOR SELECT USING (true);

-- Only admins can manage roadmap items
CREATE POLICY "Admins insert roadmap" ON roadmap_items
  FOR INSERT WITH CHECK (
    auth.role() = 'authenticated' AND EXISTS (
      SELECT 1 FROM profiles
      WHERE profiles.id = auth.uid()
      AND profiles.role ILIKE '%admin%'
    )
  );

CREATE POLICY "Admins update roadmap" ON roadmap_items
  FOR UPDATE USING (
    auth.role() = 'authenticated' AND EXISTS (
      SELECT 1 FROM profiles
      WHERE profiles.id = auth.uid()
      AND profiles.role ILIKE '%admin%'
    )
  );

CREATE POLICY "Admins delete roadmap" ON roadmap_items
  FOR DELETE USING (
    auth.role() = 'authenticated' AND EXISTS (
      SELECT 1 FROM profiles
      WHERE profiles.id = auth.uid()
      AND profiles.role ILIKE '%admin%'
    )
  );

-- Seed the default roadmap
INSERT INTO roadmap_items (title, description, icon, sort_order) VALUES
  ('Audio & Voice Notes', 'Record and share audio notes with classmates.', 'mic', 1),
  ('Push Notifications', 'Get notified when new notes land in your year.', 'notifications', 2),
  ('PDF Annotations on Desktop', 'Mark up PDFs on Windows, not just mobile.', 'draw', 3),
  ('Lecturer Videos', 'Upload and stream recorded lectures.', 'play_circle', 4)
ON CONFLICT DO NOTHING;
