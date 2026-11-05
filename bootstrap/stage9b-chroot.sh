#!/bin/bash
# stage9b-chroot.sh: runs inside the new system (as root), started by stage9b.sh.
#
# The X.Org server (Xorg), the LightDM login screen and the Xfce 4.20 desktop,
# plus what they share with the other GTK desktops: VTE, dconf, gvfs, the
# polkit agent, nm-applet, the Adwaita icons and librsvg (with Rust) to draw
# them. NVIDIA's package is rebuilt
# to add its Xorg driver. Nothing is switched over: SDDM stays the login
# screen, and Xfce appears in its session list.
set -euo pipefail
umask 022

die() { echo "stage9b: $*" >&2; exit 1; }

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

# The X server and the tools X sessions use
install_each xorg-server xf86-input-libinput xauth iceauth xrdb setxkbmap xinit xset xrandr xprop
fpm list | grep -q '^nvidia ' && install_each nvidia

# Rust, for librsvg: the SVG loader GTK needs to draw most icons
install_each rust cargo-c librsvg

# Libraries and shared pieces
install_each startup-notification libwnck3 libnotify iso-codes libxklavier libgtop libyaml libexif \
    gtk-layer-shell gtksourceview4 adwaita-icon-theme dconf perl-xml-parser intltool \
    fmt fast_float simdutf vte3 polkit-gnome libnma network-manager-applet gvfs

# Xfce
install_each libxfce4util xfconf libxfce4ui garcon exo libxfce4windowing xfce4-panel thunar \
    thunar-volman tumbler xfce4-settings xfwm4 xfdesktop xfce4-session xfce4-appfinder \
    xfce4-power-manager xfce4-notifyd xfce4-terminal mousepad ristretto xfce4-screenshooter \
    xfce4-pulseaudio-plugin

# The login screen (its greeter is built with exo and xfce4-dev-tools). Installed, not
# enabled: the installer enables it for the GTK desktops.
install_each xfce4-dev-tools lightdm lightdm-gtk-greeter flash-xfce

echo
echo "Stage 9b complete: $(fpm list | wc -l) packages installed"
