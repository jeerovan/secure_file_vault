ALTER TABLE vault_upload ADD COLUMN IF NOT EXISTS cleanup_cursor jsonb NOT NULL DEFAULT '{}'::jsonb;
