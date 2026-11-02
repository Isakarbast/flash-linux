#!/bin/bash
# stage3-chroot.sh: runs inside the new system (as root), started by stage3.sh.
#
# Creates the essential files, builds the remaining temporary tools and fpm,
# then removes the cross toolchain. Logs and stamps live in /sources.
set -euo pipefail
umask 022
export LC_ALL=POSIX

STAMPS=/sources/.stage3
LOGS=/sources/logs
BUILD=/sources/build
mkdir -p "$STAMPS" "$LOGS"

die() { echo "stage3: $*" >&2; exit 1; }

# unpack TARBALL: extract into a fresh $BUILD and cd into the source dir.
unpack() {
    rm -rf "$BUILD"
    mkdir -p "$BUILD"
    tar --no-same-owner -xf "/sources/$1" -C "$BUILD"
    cd "$BUILD/${1%.tar.*}"
}

# step NAME: run build_NAME once, logging to $LOGS/NAME.log.
step() {
    [ -e "$STAMPS/$1" ] && { echo "==> $1 (already done)"; return; }
    echo "==> $1"
    local start=$SECONDS
    # In the background, so set -e still applies inside the build.
    ( "build_$1" ) >"$LOGS/$1.log" 2>&1 &
    if ! wait $!; then
        tail -n 30 "$LOGS/$1.log" >&2
        die "$1 failed; full log: $LOGS/$1.log"
    fi
    touch "$STAMPS/$1"
    echo "    done in $(( (SECONDS - start) / 60 ))m $(( (SECONDS - start) % 60 ))s"
}

# ---- build steps -----------------------------------------------------------

build_essentials() {
    mkdir -p /etc/opt /lib/firmware /media/cdrom /usr/lib/locale \
        /usr/share/{color,dict,doc,info,locale,man,misc,terminfo,zoneinfo} \
        /usr/local/share/{color,dict,doc,info,locale,man,misc,terminfo,zoneinfo} \
        /var/{cache,local,log,mail,opt,spool} /var/lib/{color,misc,locate,hwclock}
    for i in 1 2 3 4 5 6 7 8; do mkdir -p /usr/share/man/man$i /usr/local/share/man/man$i; done

    ln -sfn /proc/self/mounts /etc/mtab

    [ -e /etc/hosts ] || cat > /etc/hosts <<'EOF'
127.0.0.1  localhost
::1        localhost
EOF

    [ -e /etc/passwd ] || cat > /etc/passwd <<'EOF'
root:x:0:0:root:/root:/bin/bash
bin:x:1:1::/:/usr/bin/nologin
daemon:x:2:2::/:/usr/bin/nologin
mail:x:8:12::/var/spool/mail:/usr/bin/nologin
ftp:x:14:14::/srv/ftp:/usr/bin/nologin
http:x:33:33::/srv/http:/usr/bin/nologin
uuidd:x:80:80::/var/lib/uuidd:/usr/bin/nologin
nobody:x:65534:65534:Unprivileged user:/:/usr/bin/nologin
EOF

    [ -e /etc/group ] || cat > /etc/group <<'EOF'
root:x:0:
bin:x:1:daemon
daemon:x:2:
sys:x:3:
adm:x:4:
tty:x:5:
disk:x:6:
lp:x:7:
mem:x:8:
kmem:x:9:
wheel:x:10:
floppy:x:11:
mail:x:12:
cdrom:x:13:
ftp:x:14:
tape:x:17:
dialout:x:18:
log:x:19:
audio:x:20:
video:x:21:
utmp:x:22:
input:x:24:
kvm:x:25:
render:x:26:
scanner:x:27:
storage:x:28:
rfkill:x:29:
uucp:x:30:
sgx:x:31:
http:x:33:
games:x:50:
lock:x:54:
uuidd:x:80:
network:x:90:
users:x:100:
nobody:x:65534:
EOF

    touch /var/log/{btmp,lastlog,faillog,wtmp}
    chgrp utmp /var/log/lastlog
    chmod 664 /var/log/lastlog
    chmod 600 /var/log/btmp
}

build_gettext() {
    unpack gettext-1.0.tar.xz
    ./configure --disable-shared
    make
    # Only the three programs other packages need to build.
    cp gettext-tools/src/{msgfmt,msgmerge,xgettext} /usr/bin
}

build_bison() {
    unpack bison-3.8.2.tar.xz
    ./configure --prefix=/usr --docdir=/usr/share/doc/bison-3.8.2
    make
    make install
}

build_perl() {
    unpack perl-5.44.0.tar.xz
    local lib=/usr/lib/perl5/5.44
    sh Configure -des \
        -D prefix=/usr \
        -D vendorprefix=/usr \
        -D useshrplib \
        -D privlib=$lib/core_perl \
        -D archlib=$lib/core_perl \
        -D sitelib=$lib/site_perl \
        -D sitearch=$lib/site_perl \
        -D vendorlib=$lib/vendor_perl \
        -D vendorarch=$lib/vendor_perl
    make
    make install
}

build_python() {
    unpack Python-3.14.10.tar.xz
    ./configure --prefix=/usr \
        --enable-shared \
        --without-ensurepip \
        --without-static-libpython
    make
    make install
}

build_texinfo() {
    unpack texinfo-7.3.tar.xz
    ./configure --prefix=/usr
    make
    make install
}

build_util_linux() {
    unpack util-linux-2.42.4.tar.xz
    ./configure --prefix=/usr \
        --libdir=/usr/lib \
        --runstatedir=/run \
        --disable-chfn-chsh \
        --disable-login \
        --disable-nologin \
        --disable-su \
        --disable-setpriv \
        --disable-runuser \
        --disable-pylibmount \
        --disable-static \
        --disable-liblastlog2 \
        --without-python \
        ADJTIME_PATH=/var/lib/hwclock/adjtime \
        --docdir=/usr/share/doc/util-linux-2.42.4
    make
    make install
}

build_zstd() {
    unpack zstd-1.5.7.tar.gz
    make prefix=/usr
    make prefix=/usr install
    rm -f /usr/lib/libzstd.a
}

build_fpm() {
    cd /sources/fpm
    make clean
    make
    make install PREFIX=/usr
    mkdir -p /var/db/fpm/recipes/main /var/lib/fpm /var/cache/fpm /etc/fpm/hooks /etc/fpm/keys
    # glibc isn't an fpm package yet, so its libraries count as always present.
    grep -q '^shlib_ignore' /etc/fpm.conf ||
        sed -i 's/^# shlib_ignore = libc.so.6$/shlib_ignore = libc.so.6 libm.so.6 libstdc++.so.6 libgcc_s.so.1/' /etc/fpm.conf
    fpm -V
    fpm list
}

build_cleanup() {
    rm -rf /usr/share/{info,man,doc}/*
    find /usr/lib /usr/libexec -name '*.la' -delete
    # The cross toolchain is no longer needed: the system has its own gcc now.
    rm -rf /tools
}

# ---- main ------------------------------------------------------------------

for s in essentials gettext bison perl python texinfo util_linux zstd fpm cleanup; do
    step "$s"
done
rm -rf "$BUILD"
echo "Stage 3 complete: the new system has its own tools and fpm"
