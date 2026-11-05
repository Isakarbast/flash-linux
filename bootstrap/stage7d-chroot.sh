#!/bin/bash
# stage7d-chroot.sh: runs inside the new system (as root), started by stage7d.sh.
#
# The everyday desktop apps: Dolphin (with kio-extras for sftp, phones, man
# pages and thumbnails), kitty (built with Go) and Firefox (Mozilla's official
# binary, on GTK 3). RTKit lets PipeWire run its audio threads at realtime
# priority. glib is rebuilt to ship its GSettings schema and GIO module hooks.
set -euo pipefail
umask 022

die() { echo "stage7d: $*" >&2; exit 1; }

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

install_each glib rtkit \
    fribidi cairo pango at-spi2-core hicolor-icon-theme gsettings-desktop-schemas gtk3 firefox \
    libssh libmtp baloo-widgets kio-extras ffmpegthumbs dolphin \
    go shader-slang xxhash simde kitty \
    flash-kde-settings

echo
echo "Stage 7d complete: $(fpm list | wc -l) packages installed"
