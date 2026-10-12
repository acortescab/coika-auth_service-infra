#!/bin/bash
# Starts PostgreSQL with docker compose. Credentials come from SSM, the container binds only the
# private IP, and it refuses to start if the data volume is not mounted (otherwise Docker would
# silently initialise an empty database on the root disk, hiding the real data).
set -euo pipefail

# shellcheck disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

mountpoint -q "$DATA_DIR" || {
  echo "Error: $DATA_DIR is not mounted; refusing to start PostgreSQL on the root disk" >&2
  exit 1
}

load_db_params
POSTGRES_PASSWORD="$(ssm_get POSTGRES_PASSWORD)"
DB_BIND_IP="$(imds local-ipv4)"
export POSTGRES_PASSWORD DB_BIND_IP

cd "$DB_DIR"
docker compose up -d
