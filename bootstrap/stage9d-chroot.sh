#!/bin/bash
# stage9d-chroot.sh: runs inside the new system (as root), started by stage9d.sh.
#
# Hyprland and the hyprwm libraries it is built from (hyprutils, hyprlang,
# aquamarine, hyprgraphics, hyprcursor, hyprtoolkit, ...), the general C++
# libraries they need (abseil and re2, sdbus-c++, tomlplusplus, glaze, ...),
# Hyprland's screen locker, idle daemon and screen-sharing portal. It shares
# Waybar, fuzzel and mako with MangoWC (stage 9c).
set -euo pipefail
umask 022

die() { echo "stage9d: $*" >&2; exit 1; }

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

# General libraries
install_each pugixml tomlplusplus libzip abseil-cpp re2 iniparser muparser glaze sdbus-cpp libei

# hyprwm libraries
install_each hyprutils hyprlang hyprwayland-scanner hyprland-protocols hyprwire hyprcursor \
    hyprgraphics aquamarine hyprtoolkit hyprland-guiutils

# Hyprland and its tools
install_each hyprland xdg-desktop-portal-hyprland hyprlock hypridle flash-hyprland

echo
echo "Stage 9d complete: $(fpm list | wc -l) packages installed"
