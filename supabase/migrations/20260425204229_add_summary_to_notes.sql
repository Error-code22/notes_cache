-- Add summary column to notes table
ALTER TABLE notes ADD COLUMN IF NOT EXISTS summary TEXT;
