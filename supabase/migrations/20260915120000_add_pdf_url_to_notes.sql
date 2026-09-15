-- Add pdf_url column to store the converted PDF URL alongside the original file.
-- The original file is NEVER replaced; this is purely additive.
ALTER TABLE notes ADD COLUMN IF NOT EXISTS pdf_url TEXT;

-- Backfill index for batch conversion queries
CREATE INDEX IF NOT EXISTS idx_notes_pdf_url ON notes (id) WHERE pdf_url IS NULL AND category IN ('Slides', 'Document');
