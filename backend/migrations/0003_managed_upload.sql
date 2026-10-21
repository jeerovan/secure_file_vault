CREATE TABLE IF NOT EXISTS vault_upload (
  id text PRIMARY KEY,
  user_id integer NOT NULL REFERENCES "user"("1") ON DELETE CASCADE,
  device_uuid text NOT NULL,
  generation text NOT NULL,
  storage_id integer NOT NULL,
  provider_id integer NOT NULL,
  object_key text NOT NULL,
  part_name text NOT NULL,
  credentials jsonb NOT NULL,
  receipt_hash text NOT NULL,
  content_length bigint NOT NULL,
  sha1 text NOT NULL,
  md5 text NOT NULL,
  upload_id text,
  version_id text,
  phase text NOT NULL DEFAULT 'creating',
  uncertain text,
  operation_id text,
  retired integer NOT NULL DEFAULT 0,
  created_at bigint NOT NULL,
  updated_at bigint NOT NULL,
  lease_owner text,
  lease_until bigint NOT NULL DEFAULT 0,
  next_attempt_at bigint NOT NULL DEFAULT 0,
  attempts integer NOT NULL DEFAULT 0,
  error text
);
CREATE INDEX IF NOT EXISTS vault_upload_owner ON vault_upload(user_id, generation);
CREATE INDEX IF NOT EXISTS vault_upload_object ON vault_upload(user_id, storage_id, object_key);
CREATE INDEX IF NOT EXISTS vault_upload_due ON vault_upload(phase, next_attempt_at);
ALTER TABLE vault_upload ENABLE ROW LEVEL SECURITY;
