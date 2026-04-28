-- Create AI Usage Tracking Table
CREATE TABLE IF NOT EXISTS user_ai_usage (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    text_count INT DEFAULT 0,
    image_count INT DEFAULT 0,
    last_reset TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE user_ai_usage ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view their own usage" ON user_ai_usage FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Service role can manage all usage" ON user_ai_usage USING (true);

-- Add AI limits to app_config if they don't exist
INSERT INTO app_config (key, value) VALUES ('ai_daily_text_limit', '50') ON CONFLICT (key) DO NOTHING;
INSERT INTO app_config (key, value) VALUES ('ai_daily_image_limit', '10') ON CONFLICT (key) DO NOTHING;

-- Atomic increment function
CREATE OR REPLACE FUNCTION increment_ai_usage(user_id_param UUID, field_name TEXT)
RETURNS VOID AS $$
BEGIN
    IF field_name = 'text_count' THEN
        UPDATE user_ai_usage SET text_count = text_count + 1 WHERE user_id = user_id_param;
    ELSIF field_name = 'image_count' THEN
        UPDATE user_ai_usage SET image_count = image_count + 1 WHERE user_id = user_id_param;
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
