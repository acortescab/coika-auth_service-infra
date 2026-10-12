#!/bin/bash
# Dumps the database and uploads it to the snapshots bucket (instance role, no static credentials).
# Retention is handled by the bucket lifecycle (db_snapshots_retention_days).
# Run from cron, see README.md.
set -euo pipefail

# shellcheck disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

: "${BACKUP_BUCKET:?set BACKUP_BUCKET in settings.env}"
load_db_params

KEY="$BACKUP_PREFIX/${POSTGRES_DB}_$(date -u +%Y%m%dT%H%M%SZ).sql.gz"

# Dump to a file first: streaming straight to S3 would upload a truncated dump as if it were valid
# when pg_dump fails midway (the CLI only sees the stream end). Upload only a verified file.
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

docker exec postgres pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --no-owner | gzip > "$TMP"
gzip -t "$TMP"
[ -s "$TMP" ] || { echo "Error: dump is empty" >&2; exit 1; }

echo "Info: Uploading dump to s3://$BACKUP_BUCKET/$KEY"
aws s3 cp "$TMP" "s3://$BACKUP_BUCKET/$KEY" --only-show-errors

echo "Success: $KEY"
