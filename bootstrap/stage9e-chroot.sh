#!/bin/bash
# stage9e-chroot.sh: runs inside the new system (as root), started by stage9e.sh.
#
# The MATE 1.28 desktop: panel, Marco, Caja, the control center and settings
# daemon, session manager, screen locker, power manager, volume control,
# terminal and system monitor, with MATE's themes, icons and wallpapers. It
# shares Mousepad, Ristretto and LightDM with Xfce. libxml2 is rebuilt with
# its Python module for itstool (MATE's help pages), and libsoup 3 arrives
# with HTTPS for GLib programs (glib-networking) for the panel clock's weather.
set -euo pipefail
umask 022

die() { echo "stage9e: $*" >&2; exit 1; }

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

# Build tools and libraries
install_each libcanberra doxygen libxml2 itstool dbus-glib perl-xml-simple icon-naming-utils desktop-file-utils \
    libpsl nghttp2 glib-networking libsoup3

# MATE
install_each mate-desktop libmatekbd libmatemixer libmateweather mate-menus mate-panel marco \
    mate-settings-daemon mate-session-manager caja mate-control-center mate-polkit \
    mate-notification-daemon mate-power-manager mate-media mate-screensaver mate-terminal \
    mate-system-monitor mate-icon-theme mate-themes mate-backgrounds zenity flash-mate

echo
echo "Stage 9e complete: $(fpm list | wc -l) packages installed"
