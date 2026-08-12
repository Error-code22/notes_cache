-- ============================================================
-- SECURITY HARDENING — 2026-08-12
-- Fixes found in the RLS audit:
--   1. app_config writable by ANY authenticated user (was admin-only by design)
--   2. chunks (AI RAG) open to direct writes by any user (RPC must be the only path)
--   3. usage + cache tables publicly readable (privacy leak)
--   4. notes INSERT lacked a user_id = auth.uid() check (ownership spoofing)
-- ============================================================

-- ── 1. app_config: only admins can write ────────────────────
DROP POLICY IF EXISTS "App_config write authed" ON app_config;
DROP POLICY IF EXISTS "App_config update authed" ON app_config;

CREATE POLICY "Admins insert config" ON app_config
  FOR INSERT WITH CHECK (
    auth.role() = 'authenticated' AND EXISTS (
      SELECT 1 FROM profiles
      WHERE profiles.id = auth.uid()
      AND profiles.role ILIKE '%admin%'
    )
  );

CREATE POLICY "Admins update config" ON app_config
  FOR UPDATE USING (
    auth.role() = 'authenticated' AND EXISTS (
      SELECT 1 FROM profiles
      WHERE profiles.id = auth.uid()
      AND profiles.role ILIKE '%admin%'
    )
  );

-- ── 2. chunks: remove direct user writes, RPC-only ──────────
DROP POLICY IF EXISTS "Chunks insert authed" ON chunks;
DROP POLICY IF EXISTS "Chunks update authed" ON chunks;

-- ── 3. usage + cache: no public reads (service-role only) ───
DROP POLICY IF EXISTS "Usage public read" ON usage;
DROP POLICY IF EXISTS "Usage update own" ON usage;
DROP POLICY IF EXISTS "Usage upsert own" ON usage;
DROP POLICY IF EXISTS "Cache public read" ON cache;
DROP POLICY IF EXISTS "Cache update authed" ON cache;
DROP POLICY IF EXISTS "Cache upsert authed" ON cache;

CREATE POLICY "Service role manages usage" ON usage
  FOR ALL USING (auth.role() = 'service_role');

CREATE POLICY "Service role manages cache" ON cache
  FOR ALL USING (auth.role() = 'service_role');

-- ── 4. notes: ownership enforcement on insert ───────────────
DROP POLICY IF EXISTS "Authenticated users insert notes" ON notes;

CREATE POLICY "Users insert own notes" ON notes
  FOR INSERT WITH CHECK (
    auth.role() = 'authenticated'
    AND user_id = auth.uid()
  );

-- ── 5. profiles: remove the blanket read-all policy ─────────
-- "Authenticated users can read profiles" had USING (true) — any logged-in
-- user could read EVERY profile incl. private ones (email, friend code, bio).
-- The "public profiles or own" policy is the only read path now.
DROP POLICY IF EXISTS "Authenticated users can read profiles" ON profiles;
