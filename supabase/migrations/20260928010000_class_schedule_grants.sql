-- class_schedules was created without explicit table privileges; Supabase's
-- default privileges didn't apply, so authenticated clients hit "permission
-- denied" before RLS was ever evaluated. RLS still gates who may write.
GRANT SELECT ON public.class_schedules TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.class_schedules TO authenticated;

-- Defensive: same pattern as other app tables
GRANT USAGE ON SCHEMA public TO anon, authenticated;
