-- An account survives reset while its replacement vault has no key envelope.
-- Existing initialized accounts retain exactly their current encrypted values.
ALTER TABLE "user" ALTER COLUMN "6" DROP NOT NULL;
ALTER TABLE "user" ALTER COLUMN "7" DROP NOT NULL;
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = '"user"'::regclass AND conname = 'user_key_envelope_pair'
  ) THEN
    ALTER TABLE "user" ADD CONSTRAINT "user_key_envelope_pair"
      CHECK (("6" IS NULL) = ("7" IS NULL));
  END IF;
END $$;
