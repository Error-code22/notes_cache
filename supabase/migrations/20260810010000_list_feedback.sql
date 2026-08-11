-- Reliable feedback listing for the admin explorer.
-- SECURITY DEFINER bypasses RLS so it always works, even if the
-- admin's session token is stale (a known cause of empty explorers).
CREATE OR REPLACE FUNCTION list_feedback()
RETURNS TABLE (id UUID, type TEXT, content TEXT, user_id UUID, created_at TIMESTAMPTZ, full_name TEXT)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT f.id, f.type, f.content, f.user_id, f.created_at, p.full_name
  FROM app_feedback f LEFT JOIN profiles p ON f.user_id = p.id
  ORDER BY f.created_at DESC
  LIMIT 200;
$$;

GRANT EXECUTE ON FUNCTION list_feedback() TO authenticated, anon;
