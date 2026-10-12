
# --- PostgreSQL service and backups (appended to user_data.sh and db_data_volume.sh) ---
# Installs the db/ folder of this repository on the host and keeps PostgreSQL running with systemd,
# so a fresh (or replaced) database host comes up by itself. Nothing secret lives here: the credentials
# are read from SSM Parameter Store by db/start.sh with the instance role.
apt-get install -y cron

install -d -o ubuntu -g ubuntu /opt/db
%{ for name, content in files ~}
echo '${content}' | base64 -d | gunzip > "/opt/db/${name}"
%{ endfor ~}
chmod +x /opt/db/*.sh

# Non-secret settings for the scripts.
printf 'BACKUP_BUCKET=%s\n' '${backup_bucket}' > /opt/db/settings.env
printf 'SSM_PREFIX=%s\n' '${ssm_prefix}' >> /opt/db/settings.env
chown -R ubuntu: /opt/db

# start.sh fails until the SSM parameters db/POSTGRES_* exist (they are created outside Terraform),
# so systemd retries it every 30 seconds instead of needing a manual step.
cat > /etc/systemd/system/postgres-db.service <<'UNIT'
[Unit]
Description=PostgreSQL container (docker compose)
After=docker.service network-online.target
Requires=docker.service
StartLimitIntervalSec=0

[Service]
Type=oneshot
RemainAfterExit=yes
User=ubuntu
ExecStart=/opt/db/start.sh
Restart=on-failure
RestartSec=30

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable postgres-db.service
systemctl start --no-block postgres-db.service

# Scheduled dumps to the snapshots bucket.
touch /var/log/db-backup.log
chown ubuntu: /var/log/db-backup.log
echo '${backup_cron} ubuntu /opt/db/backup.sh >> /var/log/db-backup.log 2>&1' > /etc/cron.d/db-backup
chmod 644 /etc/cron.d/db-backup
