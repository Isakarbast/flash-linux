#!/bin/bash
# stage6d-chroot.sh: runs inside the new system (as root), started by stage6d.sh.
#
# Sound (ALSA, PipeWire with pipewire-pulse/-alsa/-jack, WirePlumber) and
# networking (NetworkManager with wpa_supplicant for Wi-Fi). NetworkManager
# then replaces dhcpcd as the network service.
set -euo pipefail
umask 022

die() { echo "stage6d: $*" >&2; exit 1; }

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

install_each alsa-ucm-conf alsa-lib alsa-utils lua libsndfile pipewire wireplumber libndp nettle libunistring gnutls libnl wpa-supplicant networkmanager

# NetworkManager handles wired and Wi-Fi from now on (it does DHCP itself).
rc-update del dhcpcd default >/dev/null 2>&1 || true
rc-update add NetworkManager default >/dev/null

echo "Stage 6d complete: $(fpm list | wc -l) packages installed"
