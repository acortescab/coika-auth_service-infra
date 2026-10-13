#!/bin/bash
# Restores a dump from the snapshots bucket. DESTRUCTIVE: drops the public schema first, so everything
# written since the dump is lost. Stop the API first (docker stop api on the API host).
#
# Usage: ./restore.sh [--yes] [--if-empty] [key]
#   key         a specific key (see `aws s3 ls`); the newest dump when omitted
#   --yes       do not ask for confirmation (failover automation)
#   --if-empty  do nothing if the public schema already has tables, so a second run never
#               overwrites data written after the first restore
set -euo pipefail

# shellcheck disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

: "${BACKUP_BUCKET:?set BACKUP_BUCKET in settings.env}"
load_db_params

ASSUME_YES=false
ONLY_IF_EMPTY=false
KEY=""
for arg in "$@"; do
  case "$arg" in
    --yes) ASSUME_YES=true ;;
    --if-empty) ONLY_IF_EMPTY=true ;;
    -*) echo "Error: unknown option $arg" >&2; exit 1 ;;
    *) KEY="$arg" ;;
  esac
done

if [ "$ONLY_IF_EMPTY" = true ]; then
  TABLES="$(docker exec postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tA \
    -c "SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public'")"
  if [ "$TABLES" != "0" ]; then
    echo "Info: $POSTGRES_DB already has $TABLES tables in public, nothing restored"
    exit 0
  fi
fi

if [ -z "$KEY" ]; then
  KEY="$(aws s3 ls "s3://$BACKUP_BUCKET/$BACKUP_PREFIX/" | sort | tail -n 1 | awk '{print $4}')"
  [ -n "$KEY" ] || { echo "Error: no dumps found in s3://$BACKUP_BUCKET/$BACKUP_PREFIX/" >&2; exit 1; }
  KEY="$BACKUP_PREFIX/$KEY"
fi

echo "Restoring s3://$BACKUP_BUCKET/$KEY into $POSTGRES_DB. This DROPS the public schema."
if [ "$ASSUME_YES" != true ]; then
  read -r -p "Type the database name to continue: " CONFIRM
  [ "$CONFIRM" = "$POSTGRES_DB" ] || { echo "Aborted."; exit 1; }
fi

# Download and verify first so a failed download cannot leave the schema dropped with nothing to load.
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
aws s3 cp "s3://$BACKUP_BUCKET/$KEY" - --only-show-errors | gunzip > "$TMP"
[ -s "$TMP" ] || { echo "Error: downloaded dump is empty" >&2; exit 1; }

docker exec -i postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v ON_ERROR_STOP=1 \
  -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;"
docker exec -i postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v ON_ERROR_STOP=1 --single-transaction < "$TMP"
echo "Success: restored $KEY"
