#!/bin/bash
# Starts PostgreSQL with docker compose. Credentials come from SSM and the container binds only the
# private IP.
set -euo pipefail

# shellcheck disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

load_db_params
POSTGRES_PASSWORD="$(ssm_get POSTGRES_PASSWORD)"
DB_BIND_IP="$(imds local-ipv4)"
export POSTGRES_PASSWORD DB_BIND_IP

cd "$DB_DIR"
docker compose up -d
