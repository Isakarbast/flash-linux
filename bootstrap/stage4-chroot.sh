#!/bin/bash
# stage4-chroot.sh: runs inside the new system (as root), started by stage4.sh.
#
# Installs an up-to-date fpm, writes /etc/fpm.conf, then builds and installs
# every base package with fpm in dependency order. --overwrite lets each
# package take over the files the temporary tools left behind; real conflicts
# between two packages are still refused.
set -euo pipefail
umask 022

ORDER="linux-headers iana-etc glibc tzdata zlib bzip2 xz lz4 zstd file readline pcre2 m4 bc
flex ninja pkgconf binutils gmp mpfr mpc attr acl libcap libxcrypt shadow gawk
gcc ncurses sed psmisc gettext bison grep bash libtool gdbm gperf expat
inetutils less perl autoconf automake openssl libelf libffi sqlite mpdecimal
python flit-core packaging wheel setuptools meson kmod coreutils diffutils
findutils gzip iproute2 kbd make patch tar texinfo vim procps-ng util-linux
e2fsprogs"

die() { echo "stage4: $*" >&2; exit 1; }

echo "==> Installing fpm"
( cd /sources/fpm && make clean >/dev/null && make >/dev/null && install -m 755 fpm /usr/bin/fpm ) ||
    die "fpm failed to build"

cat > /etc/fpm.conf <<'EOF'
# /etc/fpm.conf: Flash Package Manager

cflags   = -O2 -pipe -march=native
ldflags  = -Wl,-O1,--as-needed
jobs     = 0            # make -j per build; 0 = all CPUs
parallel = 2            # packages building at once
sandbox  = auto
prefer   = binary

# /bin, /sbin, /lib, /lib64 and /usr/sbin are symlinks into /usr.
usrmerge = yes
purge    = usr/share/info/dir *.la

# proxy = socks5h://127.0.0.1:9050

[recipes main]
path = /var/db/fpm/recipes/main
EOF

for p in $ORDER; do
    echo "==> $p"
    start=$SECONDS
    fpm -y --overwrite install "$p" || die "$p failed (build logs: /var/cache/fpm/logs/$p.log)"
    echo "    $(( (SECONDS - start) / 60 ))m $(( (SECONDS - start) % 60 ))s"

    if [ "$p" = glibc ] && ! fpm list | grep -q '^gcc '; then
        # The temporary gcc still has its own limits.h copies from before glibc
        # was installed; point it at the real ones (Linux From Scratch 8.5).
        dir=$(dirname "$(gcc -print-libgcc-file-name)")
        if [ -d "$dir/include-fixed" ]; then
            [ -e "$dir/include/limits.h" ]    || mv "$dir/include-fixed/limits.h" "$dir/include/limits.h"
            [ -e "$dir/include/syslimits.h" ] || mv "$dir/include-fixed/syslimits.h" "$dir/include/syslimits.h"
            rm -rf "$dir/include-fixed"/*
        fi
    fi
done

echo "==> Removing leftovers of the temporary tools"
rm -rf /usr/lib/python3.14 /usr/bin/*3.14* /usr/lib/libpython3.14* /usr/include/python3.14 \
    /usr/lib/pkgconfig/python-3.14*.pc /usr/lib/*-gdb.py
find /usr -depth -name 'x86_64-lfs-linux-gnu*' -exec rm -rf {} +
rm -rf /tmp/* /var/tmp/fpm

echo "Stage 4 complete: $(fpm list | wc -l) packages installed and managed by fpm"
