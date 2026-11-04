#!/bin/bash
# stage7a-chroot.sh: runs inside the new system (as root), started by stage7a.sh.
#
# Qt 6 and what it needs: image libraries, ICU, double-conversion, the XCB
# utilities, dav1d, NVIDIA codec headers and FFmpeg. Qt alone takes 1-2 hours.
set -euo pipefail
umask 022

die() { echo "stage7a: $*" >&2; exit 1; }

install_each() {
    local p start
    for p; do
        echo "==> $p"
        start=$SECONDS
        fpm -y --overwrite install "$p" || die "$p failed (build logs: /var/cache/fpm/logs/)"
        echo "    $(( (SECONDS - start) / 60 ))m $(( (SECONDS - start) % 60 ))s"
    done
}

echo "==> Installing fpm"
( cd /sources/fpm && make clean >/dev/null && make >/dev/null && install -m 755 fpm /usr/bin/fpm ) ||
    die "fpm failed to build"

install_each sqlite nasm double-conversion icu libjpeg-turbo libwebp libtiff xcb-util xcb-util-image xcb-util-keysyms xcb-util-renderutil xcb-util-wm xcb-util-cursor xcb-util-errors dav1d nv-codec-headers ffmpeg qt6

echo "Stage 7a complete: $(fpm list | wc -l) packages installed"
