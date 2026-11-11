#!/bin/bash
# stage10b-chroot.sh: runs inside the new system (as root), started by stage10b.sh.
#
# Flash Linux's own apps (written in Rust, github.com/Isakarbast/flash-apps):
# Flash Monitor (CPU, memory, GPUs, disks, network, processes, sensors) and
# Flash Files (the file manager, replacing Dolphin on KDE). Both build from one
# recipe, flash-apps, with its crates vendored.
set -euo pipefail
umask 022

die() { echo "stage10b: $*" >&2; exit 1; }

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

# The apps (fpm brings in Rust to build them)
install_each flash-monitor flash-files

# Desktop groups that now include them: KDE switches from Dolphin to Flash
# Files (and makes it the folder default); the tiling desktops gain the monitor.
for g in flash-kde flash-hyprland flash-sway flash-mango; do
    if fpm list | grep -q "^$g "; then
        install_each "$g"
    fi
done

echo
echo "Stage 10b complete: $(fpm list | wc -l) packages installed"
