#!/bin/bash
# stage9c-chroot.sh: runs inside the new system (as root), started by stage9c.sh.
#
# wlroots 0.20 and two tiling Wayland compositors built on it, Sway and
# MangoWC, with the tools a desktop without a desktop environment needs: a
# launcher (fuzzel), notifications (mako), a bar for MangoWC (Waybar, with
# gtkmm 3), screen locking and idle, screenshots, the clipboard and the
# screen-sharing and file-chooser portals. Both appear in the login screen's
# session list.
set -euo pipefail
umask 022

die() { echo "stage9c: $*" >&2; exit 1; }

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

# wlroots
install_each seatd libliftoff wlroots0.20 scenefx cjson

# Shared Wayland tools and portals
install_each scdoc tllist fcft fuzzel mako-notifier grim slurp wl-clipboard swaybg swayidle swaylock \
    inih xdg-desktop-portal-wlr xdg-desktop-portal-gtk

# Waybar (with its icon font) and gtkmm 3
install_each font-awesome libsigc++ glibmm cairomm pangomm atkmm gtkmm3 jsoncpp spdlog waybar

# The compositors
install_each sway mangowc flash-sway flash-mango

echo
echo "Stage 9c complete: $(fpm list | wc -l) packages installed"
