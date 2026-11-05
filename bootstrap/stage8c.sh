#!/bin/bash
# stage8c.sh: 32-bit mesa (OpenGL/Vulkan for AMD and Intel GPUs in 32-bit games).
#
# Copies the recipes in, downloads the sources, then chroots in and runs
# stage8c-chroot.sh. Run it from Fedora with the new system's partition
# mounted at $LFS:
#
#     sudo SOURCE_CACHE=$HOME/.cache/distro-sources ./stage8c.sh
#
# Environment: LFS (default /mnt/nvme0n1p1), FPM_SRC (default ../../fpm),
# SOURCE_CACHE (a directory of already-downloaded tarballs to copy from).
set -euo pipefail

LFS=${LFS:-/mnt/nvme0n1p1}
HERE=$(cd "$(dirname "$0")" && pwd)
FPM_SRC=${FPM_SRC:-$(cd "$HERE/../../fpm" && pwd)}
RECIPES=$(cd "$HERE/../recipes" && pwd)

die() { echo "stage8c: $*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "run this with sudo"
mountpoint -q "$LFS" || die "mount the new system's partition at $LFS first"
[ -e "$LFS/var/lib/fpm/installed/steam" ] || die "run stage8b.sh first"

. "$HERE/vfs.sh"
. "$HERE/sync.sh"

sync_recipes
install -m 755 "$HERE/stage8c-chroot.sh" "$LFS/sources/stage8c-chroot.sh"
fetch_sources

mount_vfs
trap umount_vfs EXIT

echo "==> Entering the chroot"
# A private mount namespace: Fedora mounts / as shared, and bwrap (fpm's build
# sandbox) can't pivot_root under a shared parent mount.
unshare --mount --propagation private chroot "$LFS" /usr/bin/env -i \
    HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin LANG=C.UTF-8 \
    /bin/bash --noprofile --norc /sources/stage8c-chroot.sh
