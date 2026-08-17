#!/bin/bash
# Convert the Omarchy drive entries in /etc/fstab from on-access automount
# (which unmounts after 60s idle and makes drives keep disappearing in the file
# manager) to plain boot mounts that stay mounted for the whole session.
#
# Result: every data drive is mounted at boot, owned by the login user, always
# visible in the file manager, and NEVER prompts for a password.
#
# Safe: keeps `nofail` on every entry, so a missing/failed drive can never block
# boot. Backs up /etc/fstab first. Reversible via the printed backup path.
#
# Run with:  sudo bash fix-drive-mounts.sh

set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Please run with sudo:  sudo bash fix-drive-mounts.sh"; exit 1; }

FSTAB=/etc/fstab
STAMP="$(date +%s)"
BACKUP="$FSTAB.bak.$STAMP"

if ! grep -qE 'x-systemd\.automount' "$FSTAB"; then
  echo "Nothing to do — no x-systemd.automount entries found in $FSTAB."
  echo "(Your drives are probably already set to mount at boot.)"
  exit 0
fi

cp "$FSTAB" "$BACKUP"
echo "==> Backed up $FSTAB -> $BACKUP"

# Strip the on-access automount options from every fstab line that has them.
# These substrings only ever appear on the drive-automount lines, so a global
# edit is safe. `nofail` and the uid/gid/umask ownership options are preserved.
sed -i -E \
  -e 's/,x-systemd\.automount//g' \
  -e 's/,x-systemd\.idle-timeout=[0-9]+//g' \
  -e 's/x-systemd\.automount,//g' \
  -e 's/x-systemd\.idle-timeout=[0-9]+,//g' \
  "$FSTAB"

echo "==> Rewrote drive entries to mount at boot:"
grep -E '/mnt/' "$FSTAB" | sed 's/^/     /'

# Validate the new fstab before relying on it.
if ! findmnt --verify --tab-file "$FSTAB" >/dev/null 2>&1; then
  echo "!! fstab verification reported issues; restoring backup."
  cp "$BACKUP" "$FSTAB"
  exit 1
fi

systemctl daemon-reload

# Tear down any lingering .automount units, then mount everything now.
systemctl stop 'mnt-*.automount' 2>/dev/null || true
mount -a 2>&1 | sed 's/^/     /' || true

echo
echo "==> Currently mounted data drives:"
findmnt -rno TARGET,SOURCE,FSTYPE /mnt/* 2>/dev/null | sed 's/^/     /' || true

echo
echo "DONE. All drives now mount at boot and stay mounted — no password needed."
echo "If anything looks off, restore with:  sudo cp $BACKUP $FSTAB && sudo systemctl daemon-reload"
