# DB Backup & Restore

## Backups
- Script: `scripts/db_backup.sh` — `pg_dump` (custom format) of `DATABASE_URL` via
  `postgres:17-alpine`, written to `/root/backups/arteq-YYYY-MM-DD-HHMM.dump`, 7-day rotation.
- Schedule (install once, as root on the VPS):
  ```bash
  (crontab -l 2>/dev/null; echo '15 2 * * * /root/arteq/scripts/db_backup.sh >> /var/log/arteq-backup.log 2>&1') | crontab -
  ```
- Verify any dump without restoring:
  ```bash
  docker run --rm -v /root/backups:/b postgres:17-alpine pg_restore --list /b/<file>.dump | head
  ```

## Restore drill (run quarterly)
1. Pick the dump: `ls -t /root/backups | head -1`
2. Restore into a scratch database (NEVER straight over production):
   ```bash
   docker run --rm -v /root/backups:/b \
     --add-host db.vkvpgrlzbjahhrlqxbvg.supabase.co:172.18.0.1 \
     postgres:17-alpine sh -c '
       psql "$ADMIN_URL" -c "CREATE DATABASE restore_drill" &&
       pg_restore --dbname="$DRILL_URL" --no-owner --no-privileges /b/<file>.dump'
   ```
   (`ADMIN_URL` / `DRILL_URL` = the `DATABASE_URL` from `.env` with the database
   name swapped to `postgres` / `restore_drill`.)
3. Sanity-check counts match production ± the backup age:
   ```sql
   SELECT (SELECT count(*) FROM hospitals),
          (SELECT count(*) FROM appointments),
          (SELECT count(*) FROM call_logs);
   ```
4. Drop the scratch DB: `DROP DATABASE restore_drill;`
5. Log the drill date + dump file + result in this file's table below.

## Full-loss recovery order
1. Provision VPS, install docker + compose, clone repo (branch `main`).
2. Restore `.env` from the secrets store (it is NOT in git).
3. Re-create the socat unit (`/etc/systemd/system/socat-supabase.service`) if the
   DB is Supabase-over-IPv6, or point `DATABASE_URL` at the new Postgres.
4. `pg_restore` the latest dump into the fresh DB (as above, minus the drill DB).
5. `docker compose -f docker-compose.selfhost.yml up -d --build`.
6. Re-add Hostinger firewall Accept rules (22, 80, SIP ports) + Synchronize.

## Drill log
| Date | Dump | Result | Notes |
|------|------|--------|-------|
| 2026-07-02 | arteq-2026-07-02-1435.dump | pg_restore --list OK (645 TOC entries) | initial verification, no full restore |
