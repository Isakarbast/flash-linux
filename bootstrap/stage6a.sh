#!/bin/bash
# stage6a.sh: generic kernel, firmware split by vendor, NVIDIA driver.
#
# Detects which vendor firmware this PC needs (and whether it has an NVIDIA
# GPU) from lspci, copies the recipes in, downloads the sources, then chroots
# in and runs stage6a-chroot.sh. Run it from Fedora with the new system's
# partition mounted at $LFS:
#
#     sudo SOURCE_CACHE=$HOME/.cache/distro-sources ./stage6a.sh
#
# Environment: LFS (default /mnt/nvme0n1p1), FPM_SRC (default ../../fpm),
# SOURCE_CACHE (a directory of already-downloaded tarballs to copy from).
set -euo pipefail

LFS=${LFS:-/mnt/nvme0n1p1}
HERE=$(cd "$(dirname "$0")" && pwd)
FPM_SRC=${FPM_SRC:-$(cd "$HERE/../../fpm" && pwd)}
RECIPES=$(cd "$HERE/../recipes" && pwd)

die() { echo "stage6a: $*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "run this with sudo"
mountpoint -q "$LFS" || die "mount the new system's partition at $LFS first"
[ -e "$LFS/var/lib/fpm/installed/openrc" ] || die "run stage5.sh first"
command -v lspci >/dev/null || die "lspci is missing on the host"

# Vendor firmware this PC needs, judged from its PCI devices (vendor IDs).
FIRMWARE= NVIDIA=
pci=$(lspci -n | awk '{print $3}' | cut -d: -f1 | sort -u)
for id in $pci; do
    case $id in
        1002) FIRMWARE="$FIRMWARE linux-firmware-amdgpu linux-firmware-radeon" ;;
        8086) FIRMWARE="$FIRMWARE linux-firmware-intel" ;;
        10ec) FIRMWARE="$FIRMWARE linux-firmware-realtek" ;;
        14c3) FIRMWARE="$FIRMWARE linux-firmware-mediatek" ;;
        168c|17cb) FIRMWARE="$FIRMWARE linux-firmware-atheros" ;;
        14e4) FIRMWARE="$FIRMWARE linux-firmware-broadcom" ;;
        10de) NVIDIA=1 ;;
    esac
done
echo "==> Firmware for this PC:${FIRMWARE:- none extra}; NVIDIA GPU: ${NVIDIA:+yes}${NVIDIA:-no}"

. "$HERE/vfs.sh"
. "$HERE/sync.sh"

sync_recipes
install -m 755 "$HERE/stage6a-chroot.sh" "$LFS/sources/stage6a-chroot.sh"
fetch_sources

mount_vfs
trap umount_vfs EXIT

echo "==> Entering the chroot"
chroot "$LFS" /usr/bin/env -i \
    HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin \
    FIRMWARE="$FIRMWARE" NVIDIA="$NVIDIA" \
    /bin/bash --noprofile --norc /sources/stage6a-chroot.sh
