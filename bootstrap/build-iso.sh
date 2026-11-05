#!/bin/bash
# build-iso.sh: build the Flash Linux live/installer ISO.
#
# Uses the Flash Linux system on $LFS as the build machine: copies the
# recipes in, downloads any missing sources, chroots in and runs
# iso/mkiso-chroot.sh, then moves the ISO here. Run it from Fedora with the
# partition mounted, after stage 8c:
#
#     sudo SOURCE_CACHE=$HOME/.cache/distro-sources ./build-iso.sh
#
# Environment: LFS (default /mnt/nvme0n1p1), FPM_SRC (default ../../fpm),
# SOURCE_CACHE, VERSION (default 2026.11), OUT (where the ISO goes; default
# the invoking user's home).
set -euo pipefail

LFS=${LFS:-/mnt/nvme0n1p1}
HERE=$(cd "$(dirname "$0")" && pwd)
FPM_SRC=${FPM_SRC:-$(cd "$HERE/../../fpm" && pwd)}
RECIPES=$(cd "$HERE/../recipes" && pwd)
VERSION=${VERSION:-2026.11}
OUT=${OUT:-$(getent passwd "${SUDO_USER:-root}" | cut -d: -f6)}

die() { echo "build-iso: $*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "run this with sudo"
mountpoint -q "$LFS" || die "mount the new system's partition at $LFS first"
[ -e "$LFS/var/lib/fpm/installed/lib32-mesa" ] || die "run stage8c.sh first"
[ -d "$OUT" ] || die "OUT=$OUT is not a directory"

. "$HERE/vfs.sh"
. "$HERE/sync.sh"

sync_recipes
mkdir -p "$LFS/sources/iso"
install -m 755 "$HERE/iso/mkiso-chroot.sh" "$HERE/iso/init" "$LFS/sources/iso/"
install -m 644 "$HERE/iso/grub.cfg" "$LFS/sources/iso/"
fetch_sources

mount_vfs
trap umount_vfs EXIT

echo "==> Entering the chroot"
# Private mount namespace: Fedora's / is shared, which fpm's bwrap sandbox
# can't work under.
unshare --mount --propagation private chroot "$LFS" /usr/bin/env -i \
    HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin LANG=C.UTF-8 VERSION="$VERSION" \
    /bin/bash --noprofile --norc /sources/iso/mkiso-chroot.sh

iso=flash-linux-$VERSION.iso
mv "$LFS/var/tmp/iso/$iso" "$OUT/$iso"
[ -z "${SUDO_USER:-}" ] || chown "$SUDO_USER:" "$OUT/$iso"
echo "==> $OUT/$iso"
