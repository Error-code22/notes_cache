-- ============================================================
-- PRICING PLANS TABLE + COMMS VISIBILITY CONFIG — 2026-08-12
-- Plans are DB-driven so admins can add/remove them from the
-- admin dashboard without code changes.
-- ============================================================

CREATE TABLE IF NOT EXISTS pricing_plans (
  id BIGSERIAL PRIMARY KEY,
  name TEXT NOT NULL,
  price TEXT NOT NULL DEFAULT 'KSh 0',
  period TEXT NOT NULL DEFAULT 'forever',
  description TEXT DEFAULT '',
  features JSONB NOT NULL DEFAULT '[]'::jsonb,
  color TEXT DEFAULT '#607D8B',
  popular BOOLEAN NOT NULL DEFAULT false,
  sort_order INT NOT NULL DEFAULT 0,
  active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE pricing_plans ENABLE ROW LEVEL SECURITY;

-- Everyone can read plans (they're shown on the homepage + pricing page)
CREATE POLICY "Public read pricing plans" ON pricing_plans
  FOR SELECT USING (true);

-- Only admins can manage plans
CREATE POLICY "Admins insert plans" ON pricing_plans
  FOR INSERT WITH CHECK (
    auth.role() = 'authenticated' AND EXISTS (
      SELECT 1 FROM profiles
      WHERE profiles.id = auth.uid()
      AND profiles.role ILIKE '%admin%'
    )
  );

CREATE POLICY "Admins update plans" ON pricing_plans
  FOR UPDATE USING (
    auth.role() = 'authenticated' AND EXISTS (
      SELECT 1 FROM profiles
      WHERE profiles.id = auth.uid()
      AND profiles.role ILIKE '%admin%'
    )
  );

CREATE POLICY "Admins delete plans" ON pricing_plans
  FOR DELETE USING (
    auth.role() = 'authenticated' AND EXISTS (
      SELECT 1 FROM profiles
      WHERE profiles.id = auth.uid()
      AND profiles.role ILIKE '%admin%'
    )
  );

-- Seed the three default plans
INSERT INTO pricing_plans (name, price, period, description, features, color, popular, sort_order) VALUES
  ('Free', 'KSh 0', 'forever', 'Get started with the essentials',
   '["5 AI questions per day","Browse all shared notes","Basic chat rooms","Friend code system","100MB file uploads"]'::jsonb,
   '#607D8B', false, 1),
  ('Student Pro', 'KSh 250', '/month', 'For serious students who want the full toolkit',
   '["50 AI questions per day","AI lecture search (RAG)","Web search answers","Unlimited chat rooms","1GB file uploads","Priority support","Custom avatar","Read receipts"]'::jsonb,
   '#1565C0', true, 2),
  ('Campus License', 'KSh 15,000', '/semester', 'NotesCache for your entire campus',
   '["Unlimited AI for all students","Bulk student enrollment","Custom branding","Lecturer dashboard","Exam prep mode","Analytics & usage reports","50GB shared storage","Dedicated support","API access"]'::jsonb,
   '#2E7D32', false, 3)
ON CONFLICT DO NOTHING;

-- New config flag: show/hide the Communication card on the homepage
INSERT INTO app_config (key, value) VALUES ('show_comms_button', 'true')
ON CONFLICT (key) DO NOTHING;
