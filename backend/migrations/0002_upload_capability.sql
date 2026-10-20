CREATE TABLE "vault_upload_capability" (
  "user_id" integer NOT NULL REFERENCES "user"("1") ON DELETE CASCADE,
  "generation" text NOT NULL,
  "expires_at" bigint NOT NULL,
  PRIMARY KEY ("user_id", "generation")
);
ALTER TABLE "vault_upload_capability" ENABLE ROW LEVEL SECURITY;
