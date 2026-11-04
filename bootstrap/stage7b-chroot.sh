#!/bin/bash
# stage7b-chroot.sh: runs inside the new system (as root), started by stage7b.sh.
#
# KDE Frameworks 6 (68 libraries, in BLFS build order) and what they need:
# extra-cmake-modules, icon themes, DocBook, polkit-qt, qca, libcanberra,
# libgcrypt, libsecret, lmdb, barcode and calendar libraries.
set -euo pipefail
umask 022

die() { echo "stage7b: $*" >&2; exit 1; }

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

install_each which libogg libvorbis libcanberra libgpg-error libgcrypt libsecret \
    libxslt docbook-xml docbook-xsl perl-uri lmdb libqrencode libdmtx \
    zxing-cpp libical shared-mime-info aspell aspell-en extra-cmake-modules attica \
    plasma-wayland-protocols qca polkit-qt breeze-icons oxygen-icons \
    karchive kcodecs kconfig kcoreaddons kdbusaddons kdnssd kguiaddons \
    ki18n kidletime kimageformats kitemmodels kitemviews kplotting \
    kwidgetsaddons kwindowsystem networkmanager-qt solid sonnet \
    threadweaver kauth kcompletion kcrash kdoctools kpty kunitconversion \
    kcolorscheme kconfigwidgets kservice kglobalaccel kpackage kdesu \
    kiconthemes knotifications kjobwidgets ktextwidgets kxmlgui kbookmarks \
    kwallet kded kio kdeclarative kirigami kcmutils syndication knewstuff \
    frameworkintegration kparts syntax-highlighting ktexteditor kcontacts \
    kpeople bluez-qt kfilemetadata baloo krunner prison qqc2-desktop-style \
    kholidays purpose kcalendarcore kquickcharts knotifyconfig kdav \
    kstatusnotifieritem ksvg ktexttemplate kuserfeedback kmime

echo "Stage 7b complete: $(fpm list | wc -l) packages installed"
