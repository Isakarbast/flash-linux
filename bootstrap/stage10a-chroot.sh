#!/bin/bash
# stage10a-chroot.sh: runs inside the new system (as root), started by stage10a.sh.
#
# Flatpak: desktop apps from Flathub (Discord, Spotify, OBS, ...) without a
# recipe each. GnuPG checks Flathub's signatures, OSTree stores the apps,
# AppStream reads their metadata. Flathub is added when Flatpak is installed.
set -euo pipefail
umask 022

die() { echo "stage10a: $*" >&2; exit 1; }

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

# Signatures, archives and the sandbox
install_each libseccomp xdg-dbus-proxy npth libassuan libksba gnupg gpgme libarchive

# App storage and metadata, then Flatpak
install_each ostree libfyaml appstream python-pyparsing flatpak

echo
echo "Stage 10a complete: $(fpm list | wc -l) packages installed"
