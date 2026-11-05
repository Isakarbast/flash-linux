#!/bin/bash
# stage9g-chroot.sh: runs inside the new system (as root), started by stage9g.sh.
#
# Cinnamon 6.6, Linux Mint's desktop: Muffin (window manager), the Cinnamon
# shell (JavaScript on cjs), its settings (Python), session manager, settings
# daemon, screen locker and Nemo, with the X-Apps library and the Python
# modules its tools use (pure-Python ones installed from their wheels, the
# others built from source).
set -euo pipefail
umask 022

die() { echo "stage9g: $*" >&2; exit 1; }

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

# Python modules
install_each python-ptyprocess python-pexpect python-pytz python-idna python-charset-normalizer \
    python-certifi python-urllib3 python-requests python-webencodings python-tinycss2 python-pam \
    python-pyinotify python-psutil python-setproctitle python-pybind11 python-pillow

# Libraries and tools
install_each xdotool libsass sassc gsound libkeybinder3 libgnomekbd libxmlb exempi libgsf p11-kit vala gcr ibus \
    sound-theme-freedesktop xapp-symbolic-icons xapp python-xapp

# Cinnamon
install_each cinnamon-translations cinnamon-desktop cinnamon-menus muffin cinnamon-settings-daemon \
    cinnamon-session cinnamon-control-center cinnamon-screensaver nemo cinnamon flash-cinnamon

echo
echo "Stage 9g complete: $(fpm list | wc -l) packages installed"
