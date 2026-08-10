-- Guests (anon, no JWT) can donate notes and submit feedback.
-- Safe: anon rows must have user_id NULL — they can never impersonate a real user.

CREATE POLICY "Guests insert donated notes" ON donated_notes
  FOR INSERT WITH CHECK (auth.role() = 'anon' AND user_id IS NULL);

CREATE POLICY "Guests submit feedback" ON app_feedback
  FOR INSERT WITH CHECK (auth.role() = 'anon' AND user_id IS NULL);
