-- Create donated_notes table for student note donations
CREATE TABLE IF NOT EXISTS donated_notes (
  id BIGSERIAL PRIMARY KEY,
  title TEXT NOT NULL,
  lecturer_name TEXT DEFAULT 'Student Donation',
  target_year INT DEFAULT 1,
  semester INT DEFAULT 1,
  file_url TEXT,
  content TEXT DEFAULT '',
  category TEXT DEFAULT 'Donation',
  file_size INT DEFAULT 0,
  user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE donated_notes ENABLE ROW LEVEL SECURITY;

-- Anyone authenticated can read donated notes
CREATE POLICY "Authenticated read donated notes" ON donated_notes
  FOR SELECT USING (auth.role() = 'authenticated');

-- Authenticated users can insert donated notes
CREATE POLICY "Authenticated insert donated notes" ON donated_notes
  FOR INSERT WITH CHECK (auth.role() = 'authenticated' AND user_id = auth.uid());

-- Users can delete their own donated notes; admins can delete any
CREATE POLICY "Users delete own donated notes" ON donated_notes
  FOR DELETE USING (
    user_id = auth.uid()
    OR
    EXISTS (
      SELECT 1 FROM profiles
      WHERE profiles.id = auth.uid()
      AND profiles.role ILIKE '%admin%'
    )
  );

-- Create index for faster searches
CREATE INDEX idx_donated_notes_title ON donated_notes USING gin(to_tsvector('english', title));
CREATE INDEX idx_donated_notes_created ON donated_notes(created_at DESC);
