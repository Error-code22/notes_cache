-- Rolled-back diagnostic: rep roles + theme_mode on those rows
DO $$
DECLARE
  r RECORD;
  out TEXT := '';
BEGIN
  FOR r IN
    SELECT id, coalesce(full_name, '?') AS nm, coalesce(role, '<null>') AS role,
           coalesce(theme_mode, '<null>') AS tm, coalesce(theme_color::text, '<null>') AS tc
    FROM profiles
    WHERE role ILIKE '%class%' OR role ILIKE '%rep%'
    ORDER BY updated_at DESC NULLS LAST
    LIMIT 5
  LOOP
    out := out || chr(10) || r.nm || ' | role=' || r.role || ' | theme=' || r.tm || ' | color=' || r.tc;
  END LOOP;
  IF out = '' THEN out := ' (no class/rep roles found)'; END IF;

  -- also: how many profiles have theme_mode = system/null overall
  SELECT out || chr(10) || 'totals: ' ||
    (SELECT count(*)::text FROM profiles) || ' users, ' ||
    (SELECT count(*)::text FROM profiles WHERE theme_mode IS DISTINCT FROM 'dark') || ' not-dark'
  INTO out;
  RAISE EXCEPTION 'DIAG %', out;
END $$;
