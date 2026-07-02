#!/bin/sh
# Nightly logical backup of the Arteq DB — 7-day rotation.
# Uses pg_dump inside the postgres container (v16) against DATABASE_URL from .env.
# Cron: 15 2 * * * /root/arteq/scripts/db_backup.sh >> /var/log/arteq-backup.log 2>&1
set -eu

BACKUP_DIR=/root/backups
mkdir -p "$BACKUP_DIR"

URL=$(grep '^DATABASE_URL=' /root/arteq/.env | cut -d= -f2-)
[ -n "$URL" ] || { echo "DATABASE_URL not found in /root/arteq/.env"; exit 1; }

STAMP=$(date +%F-%H%M)
OUT="$BACKUP_DIR/arteq-$STAMP.dump"

# The DB hostname must resolve to the docker bridge gateway (172.18.0.1) where
# the socat IPv4->IPv6 tunnel listens on :5433 (same mapping the app/agent
# services get via extra_hosts in docker-compose.selfhost.yml).
docker run --rm \
    --add-host db.vkvpgrlzbjahhrlqxbvg.supabase.co:172.18.0.1 \
    postgres:17-alpine pg_dump --dbname="$URL" \
    --no-owner --no-privileges --format=custom > "$OUT"

# keep 7 days
find "$BACKUP_DIR" -name 'arteq-*.dump' -mtime +7 -delete

echo "backup ok: $OUT ($(du -h "$OUT" | cut -f1)) $(date -u +%FT%TZ)"
