-- Migration 035: audit_log — every mutating admin API request.
CREATE TABLE IF NOT EXISTS audit_log (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    actor       TEXT        NOT NULL,           -- token sub (email or 'admin')
    role        TEXT,
    method      TEXT        NOT NULL,
    path        TEXT        NOT NULL,
    hospital_id UUID,
    ip          TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS ix_audit_hospital_time ON audit_log(hospital_id, created_at DESC);
CREATE INDEX IF NOT EXISTS ix_audit_actor_time    ON audit_log(actor, created_at DESC);
