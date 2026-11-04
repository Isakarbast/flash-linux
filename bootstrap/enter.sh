#!/bin/bash
# enter.sh: open a root shell inside the new system (after stage 3).
#
#     sudo ./enter.sh
#
# Mounts /dev, /proc, /sys and /run into it, and unmounts them on exit.
set -euo pipefail

LFS=${LFS:-/mnt/nvme0n1p1}
HERE=$(cd "$(dirname "$0")" && pwd)

[ "$(id -u)" -eq 0 ] || { echo "enter: run this with sudo" >&2; exit 1; }
. "$HERE/vfs.sh"

mount_vfs
trap umount_vfs EXIT
# Private mount namespace so fpm's bwrap sandbox works (Fedora's / is shared).
unshare --mount --propagation private chroot "$LFS" /usr/bin/env -i \
    HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin \
    PS1='(new system) \u:\w\$ ' \
    MAKEFLAGS="-j$(nproc)" \
    /bin/bash --login
