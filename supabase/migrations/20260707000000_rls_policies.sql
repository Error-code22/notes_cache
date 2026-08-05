-- ============================================================
-- ROW LEVEL SECURITY POLICIES
-- NotesCache — applied 2026-07-07
-- ============================================================

-- ── Fix existing user_ai_usage policy ──────────────────────
-- Remove the overpermissive USING (true) policy
DROP POLICY IF EXISTS "Service role can manage all usage" ON user_ai_usage;
-- Only service role (edge function) can insert/update/delete
CREATE POLICY "Service role manages usage" ON user_ai_usage
  FOR ALL USING (auth.role() = 'service_role');

-- ── profiles ───────────────────────────────────────────────
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

-- Anyone authenticated can read public profiles
CREATE POLICY "Authenticated users read public profiles" ON profiles
  FOR SELECT USING (
    auth.role() = 'authenticated' AND (
      is_profile_public = true OR id = auth.uid()
    )
  );

-- Users can update their own profile
CREATE POLICY "Users update own profile" ON profiles
  FOR UPDATE USING (id = auth.uid());

-- Users can insert their own profile
CREATE POLICY "Users insert own profile" ON profiles
  FOR INSERT WITH CHECK (id = auth.uid());

-- Service role can manage all profiles (for admin operations)
CREATE POLICY "Service role manages profiles" ON profiles
  FOR ALL USING (auth.role() = 'service_role');

-- ── notes ──────────────────────────────────────────────────
ALTER TABLE notes ENABLE ROW LEVEL SECURITY;

-- Students see only notes for their year level; staff see all
CREATE POLICY "Users read notes by year" ON notes
  FOR SELECT USING (
    auth.role() = 'authenticated' AND (
      EXISTS (
        SELECT 1 FROM profiles
        WHERE profiles.id = auth.uid()
        AND (profiles.role ILIKE '%admin%'
          OR profiles.role ILIKE '%lecturer%'
          OR profiles.role ILIKE '%moderator%')
      )
      OR
      target_year = (
        SELECT year_level FROM profiles WHERE id = auth.uid()
      )
    )
  );

-- Authenticated users can insert notes
CREATE POLICY "Authenticated users insert notes" ON notes
  FOR INSERT WITH CHECK (
    auth.role() = 'authenticated'
  );

-- Users can delete their own notes; admins can delete any
CREATE POLICY "Users delete own notes" ON notes
  FOR DELETE USING (
    user_id = auth.uid()
    OR
    EXISTS (
      SELECT 1 FROM profiles
      WHERE profiles.id = auth.uid()
      AND profiles.role ILIKE '%admin%'
    )
  );

-- ── chat_rooms ─────────────────────────────────────────────
ALTER TABLE chat_rooms ENABLE ROW LEVEL SECURITY;

-- Users can only see rooms they are members of (member_ids is uuid[])
CREATE POLICY "Members read their rooms" ON chat_rooms
  FOR SELECT USING (
    auth.role() = 'authenticated'
    AND auth.uid() = ANY(member_ids)
  );

-- Authenticated users can create rooms
CREATE POLICY "Authenticated users create rooms" ON chat_rooms
  FOR INSERT WITH CHECK (auth.role() = 'authenticated');

-- Members can update rooms (for last_message, member_ids, etc.)
CREATE POLICY "Members update rooms" ON chat_rooms
  FOR UPDATE USING (
    auth.role() = 'authenticated'
    AND auth.uid() = ANY(member_ids)
  );

-- Only creator can delete rooms
CREATE POLICY "Creator deletes rooms" ON chat_rooms
  FOR DELETE USING (
    created_by = auth.uid()
  );

-- ── chat_messages ──────────────────────────────────────────
ALTER TABLE chat_messages ENABLE ROW LEVEL SECURITY;

-- Users can only read messages in rooms they belong to
CREATE POLICY "Members read room messages" ON chat_messages
  FOR SELECT USING (
    auth.role() = 'authenticated'
    AND EXISTS (
      SELECT 1 FROM chat_rooms
      WHERE chat_rooms.id = chat_messages.room_id
      AND auth.uid() = ANY(chat_rooms.member_ids)
    )
  );

-- Members can send messages to rooms they belong to
CREATE POLICY "Members send messages" ON chat_messages
  FOR INSERT WITH CHECK (
    auth.role() = 'authenticated'
    AND sender_id = auth.uid()
    AND EXISTS (
      SELECT 1 FROM chat_rooms
      WHERE chat_rooms.id = chat_messages.room_id
      AND auth.uid() = ANY(chat_rooms.member_ids)
    )
  );

-- Users can delete their own messages
CREATE POLICY "Users delete own messages" ON chat_messages
  FOR DELETE USING (sender_id = auth.uid());

-- ── friends ────────────────────────────────────────────────
ALTER TABLE friends ENABLE ROW LEVEL SECURITY;

-- Users can only see their own friend relationships
CREATE POLICY "Users read own friends" ON friends
  FOR SELECT USING (
    auth.role() = 'authenticated'
    AND (user_id = auth.uid() OR friend_id = auth.uid())
  );

-- Authenticated users can add friends
CREATE POLICY "Users add friends" ON friends
  FOR INSERT WITH CHECK (
    auth.role() = 'authenticated'
    AND user_id = auth.uid()
  );

-- Users can update their own friend requests
CREATE POLICY "Users update own friends" ON friends
  FOR UPDATE USING (
    auth.role() = 'authenticated'
    AND (user_id = auth.uid() OR friend_id = auth.uid())
  );

-- Users can remove their own friends
CREATE POLICY "Users delete own friends" ON friends
  FOR DELETE USING (
    auth.role() = 'authenticated'
    AND (user_id = auth.uid() OR friend_id = auth.uid())
  );

-- ── app_feedback ───────────────────────────────────────────
ALTER TABLE app_feedback ENABLE ROW LEVEL SECURITY;

-- Users can read their own feedback; admins read all
CREATE POLICY "Users read own feedback" ON app_feedback
  FOR SELECT USING (
    user_id = auth.uid()
    OR
    EXISTS (
      SELECT 1 FROM profiles
      WHERE profiles.id = auth.uid()
      AND profiles.role ILIKE '%admin%'
    )
  );

-- Authenticated users can submit feedback
CREATE POLICY "Authenticated users submit feedback" ON app_feedback
  FOR INSERT WITH CHECK (
    auth.role() = 'authenticated'
    AND user_id = auth.uid()
  );

-- ── app_config ─────────────────────────────────────────────
ALTER TABLE app_config ENABLE ROW LEVEL SECURITY;

-- Anyone authenticated can read config
CREATE POLICY "Authenticated read config" ON app_config
  FOR SELECT USING (auth.role() = 'authenticated');

-- Only service role can modify config
CREATE POLICY "Service role manages config" ON app_config
  FOR ALL USING (auth.role() = 'service_role');

-- ── app_updates ────────────────────────────────────────────
ALTER TABLE app_updates ENABLE ROW LEVEL SECURITY;

-- Anyone authenticated can read updates
CREATE POLICY "Authenticated read updates" ON app_updates
  FOR SELECT USING (auth.role() = 'authenticated');

-- Only service role can post updates
CREATE POLICY "Service role manages updates" ON app_updates
  FOR ALL USING (auth.role() = 'service_role');

-- ── ai_chat_history ────────────────────────────────────────
ALTER TABLE ai_chat_history ENABLE ROW LEVEL SECURITY;

-- Users can only read their own AI chat history
CREATE POLICY "Users read own AI history" ON ai_chat_history
  FOR SELECT USING (user_id = auth.uid());

-- Users can insert/update their own AI chat history
CREATE POLICY "Users manage own AI history" ON ai_chat_history
  FOR ALL USING (user_id = auth.uid());

-- ── chat_archives ──────────────────────────────────────────
ALTER TABLE chat_archives ENABLE ROW LEVEL SECURITY;

-- Members can read archives for rooms they belong to
CREATE POLICY "Members read room archives" ON chat_archives
  FOR SELECT USING (
    auth.role() = 'authenticated'
    AND EXISTS (
      SELECT 1 FROM chat_rooms
      WHERE chat_rooms.id = chat_archives.room_id
      AND auth.uid() = ANY(chat_rooms.member_ids)
    )
  );

-- Service role can manage archives (for archiving job)
CREATE POLICY "Service role manages archives" ON chat_archives
  FOR ALL USING (auth.role() = 'service_role');
