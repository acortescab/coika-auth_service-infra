
# --- Dedicated encrypted data volume for PostgreSQL (appended to user_data.sh) ---
# The volume is attached by Terraform after the instance starts, so wait for it to show up.
# On Nitro instances it appears as an NVMe device; this by-id symlink is stable across reboots.
DATA_DEVICE="/dev/disk/by-id/nvme-Amazon_Elastic_Block_Store_${volume_id_nodash}"
for _ in $(seq 1 60); do
  [ -e "$DATA_DEVICE" ] && break
  sleep 5
done
[ -e "$DATA_DEVICE" ] || { echo "Data volume did not attach in time" >&2; exit 1; }

# Format only a blank volume, so re-running never wipes existing data.
if ! blkid "$DATA_DEVICE" > /dev/null 2>&1; then
  mkfs.ext4 -L pgdata "$DATA_DEVICE"
fi

mkdir -p "${mount_path}"
# Immutable while nothing is mounted: if the volume ever fails to mount, writing to the bare
# directory on the root disk fails instead of silently creating an empty database there.
mountpoint -q "${mount_path}" || chattr +i "${mount_path}"

# Docker (and therefore the postgres container) only starts once the data volume is mounted.
mkdir -p /etc/systemd/system/docker.service.d
printf '[Unit]\nRequiresMountsFor=%s\n' "${mount_path}" \
  > /etc/systemd/system/docker.service.d/data-volume.conf
systemctl daemon-reload

DATA_UUID="$(blkid -s UUID -o value "$DATA_DEVICE")"
grep -q "$DATA_UUID" /etc/fstab || \
  echo "UUID=$DATA_UUID ${mount_path} ext4 defaults,nofail 0 2" >> /etc/fstab
mount -a
