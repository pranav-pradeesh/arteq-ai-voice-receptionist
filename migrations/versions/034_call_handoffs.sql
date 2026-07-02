-- Migration 034: call_handoffs — every automatic/requested transfer to a human,
-- with the conversation context so reception knows what the caller needs.
CREATE TABLE IF NOT EXISTS call_handoffs (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    hospital_id     UUID        REFERENCES hospitals(id),
    call_id         TEXT,
    room_name       TEXT,
    reason          TEXT        NOT NULL,
    to_phone        TEXT,
    transcript_tail TEXT,       -- last turns of the conversation at handoff time
    succeeded       BOOLEAN,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS ix_handoffs_hospital ON call_handoffs(hospital_id, created_at DESC);
