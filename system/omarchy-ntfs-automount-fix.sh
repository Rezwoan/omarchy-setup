#!/bin/bash
# Make the NTFS data drives (Files, Dev, Study, Windows) auto-mount read-write
# at boot with NO password, even after Windows Fast Startup.
#
# THE PROBLEM
#   Windows Fast Startup / an unclean dismount leaves each NTFS volume with a
#   "dirty" flag. The in-kernel `ntfs3` driver REFUSES to mount a dirty volume
#   read-write ("volume is dirty and 'force' flag is not set!"), so the fstab
#   boot-mount fails. Because the entries use `nofail`, the failure is silent
#   and the drive simply isn't there — and clicking it in the file manager
#   retries the same failing mount, showing "wrong fs type / missing helper
#   program".
#
# THE FIX
#   Mount with the userspace `ntfs-3g` FUSE driver instead of the kernel
#   `ntfs3` driver. `ntfs-3g` replays the NTFS journal itself and mounts a
#   merely-dirty volume read-write without complaint (it still safely refuses a
#   genuinely HIBERNATED volume, which `nofail` then skips). No `ntfsfix`, no
#   extra service, no network needed — `ntfs-3g` is already installed.
#
#   This script rewrites the four NTFS fstab lines from `ntfs3` to `ntfs-3g`
#   and removes the earlier (dead) dirty-flag service if present.
#
# SAFETY
#   Backs up /etc/fstab, validates with `findmnt --verify`, and restores the
#   backup on any problem. The permanent cure is disabling "Fast Startup" in
#   Windows — see the note printed at the end.
#
# Run with:  sudo bash omarchy-ntfs-automount-fix.sh

set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Please run with sudo:  sudo bash omarchy-ntfs-automount-fix.sh"; exit 1; }

FSTAB=/etc/fstab
STAMP="$(date +%s)"
DEAD_SERVICE=omarchy-ntfs-fix.service
DEAD_HELPER=/usr/local/bin/omarchy-ntfs-dirty-fix

# UUIDs of the NTFS data drives this machine auto-mounts. EDIT for a new machine.
UUIDS=(
  5C8275718275510E   # Files
  9C64263364261116   # Dev
  1842602F426013B2   # Study
  98CE4C2DCE4C064A   # Windows
)

say() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }

command -v mount.ntfs-3g >/dev/null 2>&1 || command -v ntfs-3g >/dev/null 2>&1 || {
  echo "!! ntfs-3g is not installed. Install it first:  sudo pacman -S --needed ntfs-3g"
  exit 1
}

# --------------------------------------------------- 1. tear down the dead service
if systemctl list-unit-files "$DEAD_SERVICE" >/dev/null 2>&1 \
   && systemctl cat "$DEAD_SERVICE" >/dev/null 2>&1; then
  say "Removing obsolete $DEAD_SERVICE (ntfs-3g needs no dirty-flag step)"
  systemctl disable "$DEAD_SERVICE" >/dev/null 2>&1 || true
  rm -f "/etc/systemd/system/$DEAD_SERVICE"
fi
rm -f "$DEAD_HELPER"

# --------------------------------------------------- 2. rewrite fstab entries
cp "$FSTAB" "$FSTAB.bak.$STAMP"
say "Backed up $FSTAB -> $FSTAB.bak.$STAMP"

for u in "${UUIDS[@]}"; do
  # On this UUID's line: ntfs3 -> ntfs-3g, and drop the dead x-systemd.requires.
  sed -i -E \
    -e "/UUID=$u[[:space:]]/ s/([[:space:]])ntfs3([[:space:]])/\1ntfs-3g\2/" \
    -e "/UUID=$u[[:space:]]/ s/,x-systemd\.requires=$DEAD_SERVICE//" \
    "$FSTAB"
done

say "NTFS fstab entries now:"
grep -iE "ntfs-3g" "$FSTAB" | sed 's/^/     /'

if ! findmnt --verify --tab-file "$FSTAB" >/dev/null 2>&1; then
  echo "!! fstab verification reported issues; restoring backup."
  cp "$FSTAB.bak.$STAMP" "$FSTAB"
  exit 1
fi

# --------------------------------------------------- 3. apply now
systemctl daemon-reload
say "Mounting all drives"
# Make sure nothing is half-mounted from earlier attempts, then mount fresh.
for u in "${UUIDS[@]}"; do
  dev="$(blkid -U "$u" 2>/dev/null)" || continue
  mp="$(findmnt -rno TARGET "$dev" 2>/dev/null || true)"
  [[ -n $mp ]] && umount "$dev" 2>/dev/null || true
done
mount -a 2>&1 | sed 's/^/     /' || true

echo
say "Currently mounted data drives:"
findmnt -rno TARGET,SOURCE,FSTYPE /mnt/* 2>/dev/null | sed 's/^/     /' || echo "     (none — check output above)"

cat <<'NOTE'

────────────────────────────────────────────────────────────────
DONE. The drives now auto-mount read-write at every boot, no password.

PERMANENT CURE (recommended): turn off Windows Fast Startup so the
volumes always close cleanly:
  Windows → Control Panel → Power Options
    → "Choose what the power buttons do"
    → "Change settings that are currently unavailable"
    → uncheck "Turn on fast startup" → Save changes
Then do a full Shut down (not Restart-into-Linux) once from Windows.

ntfs-3g mounts a merely-dirty volume fine. If a drive is ever left
genuinely HIBERNATED by Windows, ntfs-3g refuses it (safe) and nofail
skips it — plug that gap by disabling Fast Startup as above.
────────────────────────────────────────────────────────────────
NOTE
