#!/bin/bash
# stage5.sh: make the new system bootable.
#
# Copies the recipes in, downloads the sources, then chroots in and runs
# stage5-chroot.sh: kernel, firmware, eudev, OpenRC, GRUB, networking, sudo,
# this machine's settings, GRUB on the shared EFI partition, and passwords.
# Finally it adds a "Flash Linux" entry to the firmware's boot menu and
# boots it once on the next restart; after that the PC starts Fedora again
# unless you choose otherwise (see the message at the end).
#
#     sudo ./stage5.sh
#
# Environment: LFS (default /mnt/nvme0n1p1), FPM_SRC (default ../../fpm),
# SOURCE_CACHE (a directory of already-downloaded tarballs to copy from).
set -euo pipefail

LFS=${LFS:-/mnt/nvme0n1p1}
HERE=$(cd "$(dirname "$0")" && pwd)
FPM_SRC=${FPM_SRC:-$(cd "$HERE/../../fpm" && pwd)}
RECIPES=$(cd "$HERE/../recipes" && pwd)
LABEL="Flash Linux"

die() { echo "stage5: $*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "run this with sudo"
[ -e "$LFS/var/lib/fpm/installed/e2fsprogs" ] || die "run stage4.sh first"
[ -d /sys/firmware/efi ] || die "this PC isn't booted in UEFI mode"
mountpoint -q /boot/efi || die "the EFI partition isn't mounted at /boot/efi"
command -v efibootmgr >/dev/null || die "efibootmgr is missing on the host"

# This machine's details, taken from the running Fedora.
root_dev=$(findmnt -no SOURCE "$LFS")
esp_dev=$(findmnt -no SOURCE /boot/efi)
ROOT_UUID=$(blkid -s UUID -o value "$root_dev")
ESP_UUID=$(blkid -s UUID -o value "$esp_dev")
TIMEZONE=$(readlink /etc/localtime | sed 's|.*zoneinfo/||')
case $(localectl status 2>/dev/null | sed -n 's/.*VC Keymap: *//p') in
    se|sv-latin1) KEYMAP=sv-latin1 ;;
    '' | n/a)     KEYMAP=us ;;
    *)            KEYMAP=$(localectl status | sed -n 's/.*VC Keymap: *//p') ;;
esac
echo "==> Root $root_dev (UUID $ROOT_UUID), EFI $esp_dev, timezone $TIMEZONE, keymap $KEYMAP"

. "$HERE/vfs.sh"
. "$HERE/sync.sh"

sync_recipes
install -m 755 "$HERE/stage5-chroot.sh" "$LFS/sources/stage5-chroot.sh"
fetch_sources

cleanup() {
    mountpoint -q "$LFS/boot/efi" && umount "$LFS/boot/efi"
    umount_vfs
}
mount_vfs
mkdir -p "$LFS/boot/efi"
mountpoint -q "$LFS/boot/efi" || mount --bind /boot/efi "$LFS/boot/efi"
trap cleanup EXIT

echo "==> Entering the chroot"
chroot "$LFS" /usr/bin/env -i \
    HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin \
    ROOT_UUID="$ROOT_UUID" ESP_UUID="$ESP_UUID" TIMEZONE="$TIMEZONE" KEYMAP="$KEYMAP" \
    /bin/bash --noprofile --norc /sources/stage5-chroot.sh

# Firmware boot entry: created without changing the boot order, then used for
# the next boot only.
if ! efibootmgr | grep -q "$LABEL"; then
    disk=/dev/$(lsblk -no PKNAME "$esp_dev")
    part=$(cat "/sys/class/block/${esp_dev##*/}/partition")
    efibootmgr -q -C -d "$disk" -p "$part" -L "$LABEL" -l '\EFI\flash\grubx64.efi'
fi
num=$(efibootmgr | sed -n "s/^Boot\([0-9A-F]\{4\}\)\*\{0,1\} $LABEL.*/\1/p" | head -1)
[ -n "$num" ] || die "could not create the boot entry"
efibootmgr -q -n "$num"

cat <<EOF

Done. On the next restart the PC boots "$LABEL" once (GRUB menu, with a
Fedora entry too); after that it starts Fedora as before.
  - Boot it again later: pick "$LABEL" in the firmware boot menu, or run
      sudo efibootmgr -n $num
  - Make it the default: put $num first in the boot order shown by
      sudo efibootmgr
    e.g. sudo efibootmgr -o $num,<the rest of the current order>
EOF
