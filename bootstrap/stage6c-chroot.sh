#!/bin/bash
# stage6c-chroot.sh: runs inside the new system (as root), started by stage6c.sh.
#
# The graphics stack: cmake, the X client libraries, Wayland, keyboard layouts,
# libdrm, Vulkan loader and SPIR-V tools, LLVM with clang, and mesa. Then, if
# the NVIDIA driver is installed, its upgrade with the Wayland/GBM platform
# libraries.
set -euo pipefail
umask 022

die() { echo "stage6c: $*" >&2; exit 1; }

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

install_each cmake libxml2 mako pyyaml wayland wayland-protocols libfs libice \
    libsm libxscrnsaver libxt libxmu libxpm libxaw libxfixes \
    libxcomposite libxrender libxcursor libxdamage libfontenc libxfont2 \
    libxft libxi libxinerama libxrandr libxres libxtst libxv libxvmc \
    libxxf86dga libxxf86vm libpciaccess libxkbfile libxshmfence \
    libxpresent xkeyboard-config libxkbcommon libdrm vulkan-headers \
    vulkan-loader spirv-headers spirv-tools glslang llvm \
    spirv-llvm-translator mesa

if fpm list | grep -q '^nvidia '; then
    install_each nvidia
fi

echo "Stage 6c complete: $(fpm list | wc -l) packages installed"
