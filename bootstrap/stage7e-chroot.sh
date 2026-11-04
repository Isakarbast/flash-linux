#!/bin/bash
# stage7e-chroot.sh: runs inside the new system (as root), started by stage7e.sh.
#
# udisks2 (started on demand over D-Bus) and the storage libraries it needs:
# libblockdev with its partition, filesystem, encryption (cryptsetup), RAID,
# NVMe and SMART plugins, and LVM's device-mapper library.
set -euo pipefail
umask 022

die() { echo "stage7e: $*" >&2; exit 1; }

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

install_each libaio popt keyutils lvm2 cryptsetup libatasmart libbytesize libnvme \
    libblockdev udisks2

echo
echo "Stage 7e complete: $(fpm list | wc -l) packages installed"
