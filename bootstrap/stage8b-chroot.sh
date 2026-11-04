#!/bin/bash
# stage8b-chroot.sh: runs inside the new system (as root), started by stage8b.sh.
#
# The 32-bit libraries Steam and 32-bit games load from the system (X11/XCB,
# libdrm, Wayland, GL dispatch, Vulkan loader, libudev, ALSA, libcrypt.so.1),
# the 32-bit half of the NVIDIA driver, Steam's launcher and Proton-GE.
set -euo pipefail
umask 022

die() { echo "stage8b: $*" >&2; exit 1; }

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

install_each lib32-libffi lib32-libxau lib32-libxdmcp lib32-libxcb lib32-libx11 \
    lib32-libxext lib32-libxrender lib32-libxfixes lib32-libxrandr lib32-libxxf86vm \
    lib32-libxshmfence lib32-libxscrnsaver lib32-libxi lib32-libxcursor lib32-libxinerama \
    lib32-libxcomposite lib32-libxdamage lib32-libdrm lib32-wayland lib32-libglvnd \
    lib32-vulkan-loader lib32-eudev lib32-alsa-lib lib32-libxcrypt lib32-nvidia \
    steam proton-ge-custom

echo
echo "Stage 8b complete: $(fpm list | wc -l) packages installed"
