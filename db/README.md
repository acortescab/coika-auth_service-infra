# Database host (PostgreSQL + S3 backups)

Terraform only prepares the host (`db.tf`): Docker, AWS CLI, and the data EBS volume mounted at
`/data/postgres`. PostgreSQL itself runs from this folder with `docker compose`. The instance role
reads the credentials from SSM Parameter Store and writes to the snapshots bucket, so no secret or
AWS credential is stored on the host.

## Prerequisites

SSM parameters (`SecureString`, under the Terraform output `ssm_parameter_prefix`, default `/coika/auth_service`):

- `/coika/auth_service/db/POSTGRES_USER`
- `/coika/auth_service/db/POSTGRES_PASSWORD`
- `/coika/auth_service/db/POSTGRES_DB`

## First setup

Reach the host with SSM Session Manager (or SSH through the API host), then:

```bash
# copy this folder to the host, e.g. from your machine through SSM/SSH
sudo mkdir -p /opt/db && sudo chown ubuntu: /opt/db
cd /opt/db
# put docker-compose.yml, lib.sh, start.sh, backup.sh, restore.sh, settings.env.example here
cp settings.env.example settings.env     # fill in BACKUP_BUCKET (output db_snapshots_bucket)
chmod +x start.sh backup.sh restore.sh
./start.sh
docker compose ps    # db should become "healthy"
```

`start.sh` refuses to start if `/data/postgres` is not a mount point, loads the credentials from SSM and
publishes port 5432 only on the host's private IP. Use `./start.sh` (not a bare `docker compose up`) every
time you recreate the container; after a reboot Docker restarts it on its own.

Put the same user/password/database in the API's `DATABASE_URL_READER` / `DATABASE_URL_WRITER` secrets,
using the host's private IP (output `db_private_ip`), e.g. `postgresql://USER:PASS@10.x.x.x:5432/NAME`.

### Hosts created before the data-volume guard

The guard that stops Docker when the volume is not mounted is added at instance creation. On an existing
host, add it by hand:

```bash
sudo mountpoint -q /data/postgres || sudo chattr +i /data/postgres   # only while unmounted
sudo mkdir -p /etc/systemd/system/docker.service.d
printf '[Unit]\nRequiresMountsFor=/data/postgres\n' | sudo tee /etc/systemd/system/docker.service.d/data-volume.conf
sudo systemctl daemon-reload
```

## Backups

Run a first backup by hand to confirm the instance role works:

```bash
./backup.sh
aws s3 ls s3://<BACKUP_BUCKET>/postgres/
```

Then schedule it (every 6 hours here; the scripts set their own `PATH`, so cron finds the AWS CLI):

```bash
( crontab -l 2>/dev/null; echo '0 */6 * * * /opt/db/backup.sh >> /var/log/db-backup.log 2>&1' ) | crontab -
sudo touch /var/log/db-backup.log && sudo chown ubuntu: /var/log/db-backup.log
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
