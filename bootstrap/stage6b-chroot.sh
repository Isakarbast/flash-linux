#!/bin/bash
# stage6b-chroot.sh: runs inside the new system (as root), started by stage6b.sh.
#
# PAM (and shadow/sudo rebuilt to use it), curl with CA certificates, glib,
# D-Bus, elogind, polkit, the input stack and the font stack; then enables
# the dbus and elogind services.
set -euo pipefail
umask 022

die() { echo "stage6b: $*" >&2; exit 1; }

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

# PAM first, then the programs that switch to it; their /etc/pam.d files
# arrive in the same package, so logging in keeps working throughout.
install_each linux-pam shadow sudo
for f in login su passwd sudo system-auth system-account system-session system-password other; do
    [ -f "/etc/pam.d/$f" ] || die "/etc/pam.d/$f is missing; logins would fail"
done

install_each ca-certificates curl \
    markupsafe jinja2 glib dbus elogind duktape polkit \
    mtdev libevdev libinput \
    libpng freetype fontconfig harfbuzz dejavu-fonts

rc-update add dbus default >/dev/null
rc-update add elogind default >/dev/null

echo "Stage 6b complete: $(fpm list | wc -l) packages installed"
