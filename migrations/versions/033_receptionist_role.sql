-- Migration 033: add 'receptionist' and 'doctor' to users.role.
-- Receptionist = front-desk day-to-day operations (appointments, callbacks,
-- bookings, patients) WITHOUT hospital configuration, billing or user admin.
-- Idempotent — safe to re-run.
ALTER TABLE users DROP CONSTRAINT IF EXISTS users_role_check;
ALTER TABLE users ADD CONSTRAINT users_role_check
    CHECK (role IN ('super_admin', 'tenant_admin', 'receptionist', 'viewer', 'doctor'));
