#!/bin/bash
# stage4.sh: rebuild the base system as fpm packages.
#
# On the host (as root) it copies the recipes and an up-to-date fpm into the
# new system and downloads every source into fpm's cache (the chroot has no
# network). Then it chroots in and runs stage4-chroot.sh, which installs the
# base packages one by one in Linux From Scratch chapter 8 order.
#
#     sudo ./stage4.sh
#
# Installed packages are skipped, so running it again resumes after a failure.
# Environment: LFS (default /mnt/nvme0n1p1), FPM_SRC (default ../../fpm),
# SOURCE_CACHE (a directory of already-downloaded tarballs to copy from).
set -euo pipefail

LFS=${LFS:-/mnt/nvme0n1p1}
HERE=$(cd "$(dirname "$0")" && pwd)
FPM_SRC=${FPM_SRC:-$(cd "$HERE/../../fpm" && pwd)}
RECIPES=$(cd "$HERE/../recipes" && pwd)

die() { echo "stage4: $*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "run this with sudo"
[ -e "$LFS/sources/.stage3/cleanup" ] || die "run stage3.sh first"
[ -f "$FPM_SRC/src/fpm.h" ] || die "fpm source not found at $FPM_SRC (set FPM_SRC)"

. "$HERE/vfs.sh"

. "$HERE/sync.sh"

sync_recipes
install -m 755 "$HERE/stage4-chroot.sh" "$LFS/sources/stage4-chroot.sh"
fetch_sources

mount_vfs
trap umount_vfs EXIT

echo "==> Entering the chroot"
chroot "$LFS" /usr/bin/env -i \
    HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin \
    /bin/bash --noprofile --norc /sources/stage4-chroot.sh
