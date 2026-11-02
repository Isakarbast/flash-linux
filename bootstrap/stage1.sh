#!/bin/bash
# stage1.sh: build the temporary cross toolchain into the new system's partition.
#
# Follows Linux From Scratch chapter 5: binutils and gcc (pass 1), the Linux API
# headers, glibc and libstdc++, all built for the target x86_64-lfs-linux-gnu.
# Tools go in $LFS/tools; glibc and the headers go in $LFS/usr. Stage 2 uses
# this toolchain to build the core tools, and the final system replaces it all.
#
# Run as your normal user (never root); see README.md for the one-time setup.
# Finished steps are remembered, so running it again resumes after a failure.
set -euo pipefail

STAGE=stage1
. "$(dirname "$0")/common.sh"

SRC_LIST="$TOOLCHAIN_SRC
glibc-$GLIBC_VER.tar.xz 37f600f2bef3c5e8300147059568b2a2e40a7ad6ccc65ce942556d49429cc667 https://mirrors.kernel.org/gnu/glibc/glibc-$GLIBC_VER.tar.xz
linux-7.3.1.tar.xz    fa595aad93734f829c963c2a90ef7c3673224fd7fdae7b49406e397cde2de231  https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-7.3.1.tar.xz
"

# ---- build steps -----------------------------------------------------------

build_binutils_pass1() {
    unpack binutils-$BINUTILS_VER.tar.xz
    mkdir build && cd build
    ../configure --prefix="$LFS/tools" \
        --with-sysroot="$LFS" \
        --target=$LFS_TGT \
        --disable-nls \
        --enable-gprofng=no \
        --disable-werror \
        --enable-new-dtags \
        --enable-default-hash-style=gnu
    make
    make install
}

build_gcc_pass1() {
    unpack_gcc
    mkdir build && cd build
    ../configure --target=$LFS_TGT \
        --prefix="$LFS/tools" \
        --with-glibc-version=$GLIBC_VER \
        --with-sysroot="$LFS" \
        --with-newlib \
        --without-headers \
        --enable-default-pie \
        --enable-default-ssp \
        --disable-nls \
        --disable-shared \
        --disable-multilib \
        --disable-threads \
        --disable-libatomic \
        --disable-libgomp \
        --disable-libquadmath \
        --disable-libssp \
        --disable-libvtv \
        --disable-libstdcxx \
        --enable-languages=c,c++
    make
    make install
    cd ..
    # A full limits.h; the one installed above assumes no libc headers yet.
    cat gcc/limitx.h gcc/glimits.h gcc/limity.h > \
        "$(dirname "$($LFS_TGT-gcc -print-libgcc-file-name)")/include/limits.h"
}

build_linux_headers() {
    unpack linux-7.3.1.tar.xz
    make mrproper
    make headers
    find usr/include -type f ! -name '*.h' -delete
    cp -r usr/include "$LFS/usr"
}

build_glibc() {
    unpack glibc-$GLIBC_VER.tar.xz
    # /lib64 is a symlink to usr/lib here, so the dynamic loader is already at
    # /lib64/ld-linux-x86-64.so.2 once glibc installs into /usr/lib.
    mkdir build && cd build
    echo "rootsbindir=/usr/sbin" > configparms
    ../configure --prefix=/usr \
        --host=$LFS_TGT \
        --build="$(../scripts/config.guess)" \
        --disable-nscd \
        libc_cv_slibdir=/usr/lib \
        --enable-kernel=5.4 \
        --with-headers="$LFS/usr/include"
    make
    make DESTDIR="$LFS" install
    sed '/RTLDLIST=/s@/usr@@g' -i "$LFS/usr/bin/ldd"

    # Sanity check: the cross compiler must link against the new glibc.
    echo 'int main(void){return 0;}' | $LFS_TGT-gcc -x c - -o "$BUILD/a.out"
    readelf -l "$BUILD/a.out" | grep -q 'interpreter: /lib64/ld-linux-x86-64.so.2' ||
        { echo "toolchain sanity check failed"; return 1; }
}

build_libstdcxx() {
    unpack gcc-$GCC_VER.tar.xz
    mkdir build && cd build
    ../libstdc++-v3/configure \
        --host=$LFS_TGT \
        --build="$(../config.guess)" \
        --prefix=/usr \
        --disable-multilib \
        --disable-nls \
        --disable-libstdcxx-pch \
        --with-gxx-include-dir=/tools/$LFS_TGT/include/c++/$GCC_VER
    make
    make DESTDIR="$LFS" install
    rm -f "$LFS"/usr/lib/lib{stdc++{,exp,fs},supc++}.la
}

# ---- main ------------------------------------------------------------------

fetch_sources
step binutils_pass1
step gcc_pass1
step linux_headers
step glibc
step libstdcxx
rm -rf "$BUILD"
echo "Stage 1 complete: cross toolchain in $LFS/tools ($LFS_TGT-gcc)"
