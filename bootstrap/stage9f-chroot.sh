#!/bin/bash
# stage9f-chroot.sh: runs inside the new system (as root), started by stage9f.sh.
#
# What Cinnamon is built on. Cinnamon's shell is JavaScript (cjs, on
# SpiderMonkey 128) and its settings are Python (PyGObject); both reach GLib,
# GTK, NetworkManager, polkit and the rest through GObject Introspection, so
# those libraries are rebuilt with their introspection data. Also the Ayatana
# AppIndicator libraries (tray icons in Waybar), which need it to build, and
# nm-applet rebuilt with them.
set -euo pipefail
umask 022

die() { echo "stage9f: $*" >&2; exit 1; }

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

# GObject Introspection and GLib need each other: the tools first, then GLib
# with its introspection data, then the tools again with theirs.
install_each gobject-introspection glib
echo "==> gobject-introspection (again, with its data)"
fpm -y --overwrite --rebuild --reinstall install gobject-introspection ||
    die "gobject-introspection failed (build logs: /var/cache/fpm/logs/)"

# The GTK stack and desktop services, rebuilt with introspection data
install_each harfbuzz gdk-pixbuf pango at-spi2-core json-glib gtk3 libnotify libgudev polkit upower \
    accountsservice libsecret networkmanager libnma gsettings-desktop-schemas libxklavier libsoup3 libwnck3

# Python and JavaScript bindings
install_each graphene pycairo pygobject dbus-python cbindgen js128 cjs

# Tray icons
install_each libdbusmenu ayatana-ido libayatana-indicator libayatana-appindicator network-manager-applet

echo
echo "Stage 9f complete: $(fpm list | wc -l) packages installed"
