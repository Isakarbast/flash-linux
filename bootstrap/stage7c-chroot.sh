#!/bin/bash
# stage7c-chroot.sh: runs inside the new system (as root), started by stage7c.sh.
#
# KDE Plasma 6 (the core desktop: KWin, workspace, settings, lock screen,
# network/volume/power applets, portals) and what it needs: Xwayland, SDDM,
# upower, accountsservice, xdg-desktop-portal, PulseAudio client libraries.
# Then the graphical login (SDDM) is enabled at boot.
set -euo pipefail
umask 022

die() { echo "stage7c: $*" >&2; exit 1; }

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

install_each boost lcms2 json-c libusb libgudev upower accountsservice pixman \
    libxcvt libepoxy libtirpc font-util xkbcomp xwayland hwdata \
    libdisplay-info fuse bubblewrap json-glib gdk-pixbuf gstreamer gst-plugins-base \
    xdg-desktop-portal qcoro qtkeychain kirigami-addons pulseaudio \
    pulseaudio-qt sddm lm-sensors libva libwacom modemmanager modemmanager-qt kdecoration libkscreen libksysguard breeze \
    layer-shell-qt plasma-activities libplasma kscreenlocker kglobalacceld \
    kwayland aurorae knighttime kwin plasma5support \
    plasma-activities-stats kpipewire plasma-workspace kmenuedit kscreen \
    kwallet-pam milou plasma-nm plasma-pa plasma-workspace-wallpapers \
    polkit-kde-agent-1 powerdevil plasma-desktop sddm-kcm \
    kactivitymanagerd plasma-integration cups qt6 xdg-desktop-portal-kde \
    kde-cli-tools systemsettings qqc2-breeze-style ksystemstats \
    ocean-sound-theme kinfocenter

# Boot to the graphical login; text logins stay on tty2-6 (Ctrl+Alt+F2).
rc-update add sddm default >/dev/null

echo "Stage 7c complete: $(fpm list | wc -l) packages installed"
