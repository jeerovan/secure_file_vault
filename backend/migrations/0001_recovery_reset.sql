CREATE TABLE "recovery_reset" (
  "id" text PRIMARY KEY NOT NULL,
  "user_id" integer NOT NULL REFERENCES "public"."user"("1") ON DELETE CASCADE,
  "expected_generation" text NOT NULL,
  "next_generation" text NOT NULL,
  "session_hash" text NOT NULL,
  "challenge_hash" text NOT NULL,
  "created_at" bigint NOT NULL,
  "expires_at" bigint NOT NULL,
  "committed_at" bigint,
  "not_before" bigint,
  "envelope_hash" text,
  "phase" text DEFAULT 'prepared' NOT NULL,
  "error" text
);
CREATE TABLE "recovery_cleanup_target" (
  "id" text PRIMARY KEY NOT NULL,
  "operation_id" text NOT NULL REFERENCES "recovery_reset"("id") ON DELETE CASCADE,
  "provider_id" integer NOT NULL,
  "prefix" text NOT NULL,
  "credentials" jsonb NOT NULL,
  "cursor" jsonb DEFAULT '{}'::jsonb NOT NULL,
  "phase" text DEFAULT 'pending' NOT NULL,
  "lease_owner" text,
  "lease_until" bigint DEFAULT 0 NOT NULL,
  "next_attempt_at" bigint DEFAULT 0 NOT NULL,
  "attempts" integer DEFAULT 0 NOT NULL,
  "error" text
);
CREATE TABLE "recovery_worker_state" (
  "id" text PRIMARY KEY NOT NULL,
  "last_run_at" bigint NOT NULL
);
CREATE TABLE "vault_state" (
  "user_id" integer PRIMARY KEY NOT NULL REFERENCES "public"."user"("1") ON DELETE CASCADE,
  "generation" text NOT NULL,
  "reset_at" bigint DEFAULT 0 NOT NULL,
  "initiating_session_hash" text,
  "ready" integer DEFAULT 1 NOT NULL
);
CREATE INDEX "recovery_cleanup_due" ON "recovery_cleanup_target" ("phase", "next_attempt_at");
CREATE INDEX "recovery_reset_user" ON "recovery_reset" ("user_id");
CREATE INDEX "recovery_reset_phase" ON "recovery_reset" ("phase");
ALTER TABLE "recovery_reset" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "recovery_cleanup_target" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "recovery_worker_state" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "vault_state" ENABLE ROW LEVEL SECURITY;
