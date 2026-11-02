#!/bin/bash
# stage6a-chroot.sh: runs inside the new system (as root), started by stage6a.sh.
#
# Replaces the machine-specific kernel with the generic one (every driver as a
# module, plus linux-devel), splits linux-firmware by vendor, and installs the
# NVIDIA driver with what it needs (X client libraries, libglvnd).
#
# FIRMWARE (from stage6a.sh) lists the vendor firmware packages this PC needs.
set -euo pipefail
umask 022

die() { echo "stage6a: $*" >&2; exit 1; }

# install PKG...: install (or upgrade) each package in turn, timing it.
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

# Generic kernel and its build files.
install_each linux linux-devel

# The firmware package now holds only the shared files; the vendor parts are
# separate packages, so upgrade it first and then add this PC's vendors.
install_each linux-firmware ${FIRMWARE}

# X client libraries (needed by NVIDIA's GLX/VDPAU libraries), then libglvnd
# and the driver.
install_each xorgproto libxau libxdmcp xcb-proto libxcb xtrans libx11 libxext libglvnd
if [ -n "${NVIDIA:-}" ]; then
    install_each nvidia
fi

echo "Stage 6a complete: $(fpm list | wc -l) packages installed"
