-- Telegram backup columns: track the backup copy of each uploaded file.
ALTER TABLE notes ADD COLUMN IF NOT EXISTS telegram_msg_id BIGINT;
ALTER TABLE notes ADD COLUMN IF NOT EXISTS telegram_file_id TEXT;
