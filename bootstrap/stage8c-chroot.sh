#!/bin/bash
# stage8c-chroot.sh: runs inside the new system (as root), started by stage8c.sh.
#
# 32-bit mesa, so 32-bit games and Steam work on AMD and Intel GPUs too (NVIDIA
# uses lib32-nvidia). It needs a 32-bit LLVM (no clang) and zlib, expat and
# zstd; mesa is rebuilt to install the shader compilers the 32-bit build runs.
set -euo pipefail
umask 022

die() { echo "stage8c: $*" >&2; exit 1; }

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

install_each mesa lib32-libpciaccess lib32-libdrm lib32-zlib lib32-expat lib32-zstd lib32-libelf lib32-llvm lib32-mesa

echo
echo "Stage 8c complete: $(fpm list | wc -l) packages installed"
