# Database host (PostgreSQL + S3 backups)

Terraform sets the whole host up (`db.tf`, `db_bootstrap.sh`): Docker, AWS CLI, this folder installed in
`/opt/db`, PostgreSQL started by the `postgres-db` systemd service (`docker compose`, data in the `pgdata`
Docker volume on the encrypted root disk) and the backup cron. The instance role reads the credentials from SSM Parameter
Store and writes to the snapshots bucket, so no secret or AWS credential is stored on the host.

## Prerequisites

SSM parameters (`SecureString`, under the Terraform output `ssm_parameter_prefix`, default `/coika/auth_service`):

- `/coika/auth_service/db/POSTGRES_USER`
- `/coika/auth_service/db/POSTGRES_PASSWORD`
- `/coika/auth_service/db/POSTGRES_DB`

## Setup

Nothing to do by hand: create the SSM parameters above and run `terraform apply`. On first boot the
`postgres-db` service runs `start.sh`; if the parameters do not exist yet it retries every 30 seconds, so it
comes up by itself as soon as you create them.

```bash
systemctl status postgres-db      # on the host: "active (exited)" once PostgreSQL has been started
docker compose -f /opt/db/docker-compose.yml ps    # db should become "healthy"
```

`start.sh` loads the credentials from SSM and publishes port 5432 only on the host's private IP. To recreate the container run `sudo systemctl restart
postgres-db` (or `/opt/db/start.sh`), not a bare `docker compose up`. After a reboot the service runs again.

The API host builds its `DATABASE_URL_*` from the same SSM parameters and the `db/DB_HOST` Terraform publishes,
so nothing else has to be configured.

### Changing the scripts in this folder

The bootstrap only runs when the instance is created (`user_data` is ignored on purpose, so an edit never
replaces the host that holds the data). The data lives on the root disk, so replacing the host
(`terraform apply -replace=aws_instance.database`) deletes it: take a backup first (`/opt/db/backup.sh`) and
restore it on the new host (see Restore).

For a quick fix without replacing it, edit the file in `/opt/db` on the host.

### Durability

The data is only on the instance's root disk. If the instance is terminated or replaced, the data is gone;
the S3 dumps (every 6 hours by default) are the recovery path, so you can lose up to that interval of data.

## Backups

Terraform installs the schedule in `/etc/cron.d/db-backup` (variable `db_backup_cron`, every 6 hours by
default) and writes the log to `/var/log/db-backup.log`. To check that the instance role works without
waiting for the next run:

```bash
/opt/db/backup.sh
aws s3 ls s3://<BACKUP_BUCKET>/postgres/
```

Dumps are `pg_dump | gzip` files under `postgres/` in the bucket. The dump is written to a temp file and
checked (`gzip -t`) before upload, so a failed run uploads nothing. The bucket is versioned, encrypted,
replicated to the DR region when configured, and expires objects after `db_snapshots_retention_days`.
Check the cron log from time to time; a failed run exits non-zero.

## Restore

```bash
docker stop api            # on the API host: nothing should write during the restore
./restore.sh               # newest dump, or ./restore.sh postgres/<file>.sql.gz
```

It asks you to type the database name, because it drops the `public` schema before loading the dump.
For automation (the failover state machine) use `./restore.sh --yes --if-empty`: no prompt, and it does
nothing if the database already has tables, so it never overwrites data written after a previous restore.

### Restore in the DR region

The scripts use the region of the instance by default. On the DR host, set `BACKUP_BUCKET` in
`settings.env` to the DR bucket (same name pattern with the DR region, see the primary's
`db_snapshots_replica_bucket` output) and create the three SSM parameters in the DR region.

## Migrating existing data from the old compose volume

If the API host still has the old `db_data` volume with real data, dump it before removing it:

```bash
# on the API host
docker compose -f docker-compose-prod.yml exec -T db pg_dump -U "$DB_USER" -d "$DB_NAME" > dump.sql
# copy dump.sql to the DB host, then (user and database as stored in SSM)
docker exec -i postgres psql -U <POSTGRES_USER> -d <POSTGRES_DB> -v ON_ERROR_STOP=1 --single-transaction < dump.sql
```
