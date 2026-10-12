#!/bin/bash
# Shared helpers for the database scripts. Source it, do not execute it.
# Credentials are read from SSM Parameter Store with the instance role: nothing secret is stored on disk.

# cron's default PATH lacks /usr/local/bin, where the AWS CLI is installed.
export PATH="/usr/local/bin:$PATH"

DB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Non-secret settings (BACKUP_BUCKET, ...), see settings.env.example.
set -a
# shellcheck disable=SC1091
[ -f "$DB_DIR/settings.env" ] && . "$DB_DIR/settings.env"
set +a

SSM_PREFIX="${SSM_PREFIX:-/coika/auth_service}"
BACKUP_PREFIX="${BACKUP_PREFIX:-postgres}"
DATA_DIR="${DATA_DIR:-/data/postgres}"

# Instance metadata (IMDSv2 is required on these hosts).
imds() {
  local token
  token="$(curl -fsS -X PUT http://169.254.169.254/latest/api/token \
    -H 'X-aws-ec2-metadata-token-ttl-seconds: 60')"
  curl -fsS -H "X-aws-ec2-metadata-token: $token" \
    "http://169.254.169.254/latest/meta-data/$1"
}

# Defaults to the region of the instance, so the DR host reads its own region's parameters.
AWS_REGION="${AWS_REGION:-$(imds placement/region)}"
export AWS_DEFAULT_REGION="$AWS_REGION"

ssm_get() {
  aws ssm get-parameter --name "$SSM_PREFIX/db/$1" --with-decryption \
    --query Parameter.Value --output text
}

load_db_params() {
  POSTGRES_USER="$(ssm_get POSTGRES_USER)"
  POSTGRES_DB="$(ssm_get POSTGRES_DB)"
  export POSTGRES_USER POSTGRES_DB
}
