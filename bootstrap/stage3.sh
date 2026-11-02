#!/bin/bash
# stage3.sh: enter the new system and finish the temporary tools there.
#
# Follows Linux From Scratch chapter 7. On the host (as root) it downloads the
# sources, gives the partition back to root, copies in fpm and mounts /dev,
# /proc, /sys and /run. Then it chroots in and runs stage3-chroot.sh, which
# creates the essential files and builds gettext, bison, perl, Python, texinfo,
# util-linux, zstd and fpm, and finally removes the cross toolchain in /tools.
#
#     sudo ./stage3.sh
#
# Finished steps are remembered, so running it again resumes after a failure.
# Environment: LFS (default /mnt/nvme0n1p1), FPM_SRC (default ../../fpm).
set -euo pipefail

LFS=${LFS:-/mnt/nvme0n1p1}
HERE=$(cd "$(dirname "$0")" && pwd)
FPM_SRC=${FPM_SRC:-$(cd "$HERE/../../fpm" && pwd)}
SOURCES=$LFS/sources

die() { echo "stage3: $*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "run this with sudo"
[ -d "$LFS/usr/bin" ] && [ -x "$LFS/usr/bin/gcc" ] || die "run stage1.sh and stage2.sh first"
[ -f "$FPM_SRC/src/fpm.h" ] || die "fpm source not found at $FPM_SRC (set FPM_SRC)"

. "$HERE/vfs.sh"

# file  sha256  url (checked against the upstream GPG signatures, or the
# checksums published by cpan.org and python.org)
SRC_LIST="
gettext-1.0.tar.xz       71132a3fb71e68245b8f2ac4e9e97137d3e5c02f415636eb508ae607bc01add7 https://mirrors.kernel.org/gnu/gettext/gettext-1.0.tar.xz
bison-3.8.2.tar.xz       9bba0214ccf7f1079c5d59210045227bcf619519840ebfa80cd3849cff5a5bf2 https://mirrors.kernel.org/gnu/bison/bison-3.8.2.tar.xz
perl-5.44.0.tar.xz       505cf43912e9480495c344c70260452e32aa2a73c546a026b3f100053b23ce91 https://www.cpan.org/src/5.0/perl-5.44.0.tar.xz
Python-3.14.10.tar.xz    de414a57119abef52784d8993e341d53aed635fc2b05c2607d9f98a2c5b72032 https://www.python.org/ftp/python/3.14.10/Python-3.14.10.tar.xz
texinfo-7.3.tar.xz       51f74eb0f51cfa9873b85264dfdd5d46e8957ec95b88f0fb762f63d9e164c72e https://mirrors.kernel.org/gnu/texinfo/texinfo-7.3.tar.xz
util-linux-2.42.4.tar.xz fbd62a100ab7bb8746ba0661255c3c48185b1e9021507c624da01fbc696330ec https://mirrors.kernel.org/pub/linux/utils/util-linux/v2.42/util-linux-2.42.4.tar.xz
zstd-1.5.7.tar.gz        eb33e51f49a15e023950cd7825ca74a4a2b43db8354825ac24fc1b7ee09e6fa3 https://github.com/facebook/zstd/releases/download/v1.5.7/zstd-1.5.7.tar.gz
"

echo "$SRC_LIST" | while read -r file sum url; do
    [ -n "$file" ] || continue
    if [ -f "$SOURCES/$file" ] && echo "$sum  $SOURCES/$file" | sha256sum -c --status; then
        continue
    fi
    echo "==> Downloading $file"
    curl -fL --retry 3 -o "$SOURCES/$file.part" "$url"
    echo "$sum  $SOURCES/$file.part" | sha256sum -c --status || die "checksum mismatch for $file"
    mv "$SOURCES/$file.part" "$SOURCES/$file"
done

# From here on everything in the new system belongs to root.
echo "==> Giving $LFS back to root"
chown -R root:root "$LFS"/{usr,etc,var,sources}
[ -d "$LFS/tools" ] && chown -R root:root "$LFS/tools"
chown -h root:root "$LFS"/{bin,sbin,lib,lib64}

echo "==> Copying in fpm and the chroot script"
rm -rf "$SOURCES/fpm"
mkdir -p "$SOURCES/fpm"
tar -C "$FPM_SRC" --exclude=.git --exclude='*.o' --exclude=./fpm -cf - . | tar -xf - -C "$SOURCES/fpm"
install -m 755 "$HERE/stage3-chroot.sh" "$SOURCES/stage3-chroot.sh"

mount_vfs
trap umount_vfs EXIT

echo "==> Entering the chroot"
chroot "$LFS" /usr/bin/env -i \
    HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin \
    MAKEFLAGS="-j$(nproc)" \
    /bin/bash --noprofile --norc /sources/stage3-chroot.sh
