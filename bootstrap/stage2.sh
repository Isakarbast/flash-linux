#!/bin/bash
# stage2.sh: cross-compile the temporary tools onto the new system's partition.
#
# Follows Linux From Scratch chapter 6: with the stage 1 cross toolchain, build
# the basic programs (shell, coreutils, make, tar, ...) into $LFS/usr, then a
# second binutils and gcc that run on the new system itself. Afterwards there is
# enough on the partition to chroot into it (stage 3).
#
# Run as your normal user (never root), after stage1.sh has finished.
# Finished steps are remembered, so running it again resumes after a failure.
set -euo pipefail

STAGE=stage2
. "$(dirname "$0")/common.sh"

[ -x "$LFS/tools/bin/$LFS_TGT-gcc" ] && [ -e "$LFS/tools/.stage1/libstdcxx" ] ||
    die "run stage1.sh first"

SRC_LIST="$TOOLCHAIN_SRC
m4-1.4.21.tar.xz f25c6ab51548a73a75558742fb031e0625d6485fe5f9155949d6486a2408ab66 https://mirrors.kernel.org/gnu/m4/m4-1.4.21.tar.xz
ncurses-6.6.tar.gz 355b4cbbed880b0381a04c46617b7656e362585d52e9cf84a67e2009b749ff11 https://mirrors.kernel.org/gnu/ncurses/ncurses-6.6.tar.gz
bash-5.3.tar.gz 0d5cd86965f869a26cf64f4b71be7b96f90a3ba8b3d74e27e8e9d9d5550f31ba https://mirrors.kernel.org/gnu/bash/bash-5.3.tar.gz
coreutils-9.12.tar.xz a480198559733e9b3da999e90543ac6f888a2caa544d8d664c5a1f17e528e210 https://mirrors.kernel.org/gnu/coreutils/coreutils-9.12.tar.xz
diffutils-3.12.tar.xz 7c8b7f9fc8609141fdea9cece85249d308624391ff61dedaf528fcb337727dfd https://mirrors.kernel.org/gnu/diffutils/diffutils-3.12.tar.xz
findutils-4.11.0.tar.xz bfd19cb06cc71f3352d567e90284d8cdac02ac89774bbeadf0b533b0c11432fd https://mirrors.kernel.org/gnu/findutils/findutils-4.11.0.tar.xz
gawk-5.4.1.tar.xz 07f6f7342b7febe4313fc2c2542ad93d64fe20ad8717200109f105a826f5fd37 https://mirrors.kernel.org/gnu/gawk/gawk-5.4.1.tar.xz
grep-3.12.tar.xz 2649b27c0e90e632eadcd757be06c6e9a4f48d941de51e7c0f83ff76408a07b9 https://mirrors.kernel.org/gnu/grep/grep-3.12.tar.xz
gzip-1.15.tar.xz 9aa0cc780dec156b8282844833b342ab7cb08c25d2cd9a1869cdd0df31deff48 https://mirrors.kernel.org/gnu/gzip/gzip-1.15.tar.xz
make-4.4.1.tar.gz dd16fb1d67bfab79a72f5e8390735c49e3e8e70b4945a15ab1f81ddb78658fb3 https://mirrors.kernel.org/gnu/make/make-4.4.1.tar.gz
patch-2.8.1.tar.xz 3240c7959c5347c8ed347e3c4201c0337bf4240d5cf09d68889e58eeaba30e17 https://mirrors.kernel.org/gnu/patch/patch-2.8.1.tar.xz
sed-4.10.tar.xz b8e72182b2ec96a3574e2998c47b7aaa64cc20ce000d8e9ac313cc07cecf28c7 https://mirrors.kernel.org/gnu/sed/sed-4.10.tar.xz
tar-1.35.tar.xz 4d62ff37342ec7aed748535323930c7cf94acf71c3591882b26a7ea50f3edc16 https://mirrors.kernel.org/gnu/tar/tar-1.35.tar.xz
file-5.48.tar.gz ed14656883b23a364b4057c05595d93252da9bc473d30106519519d0da141283 https://astron.com/pub/file/file-5.48.tar.gz
xz-5.8.4.tar.xz 4ce24038fd4221e0d13bc1a2de7a4db56e90b92b3bf75321f6c14be73f65de4b https://github.com/tukaani-project/xz/releases/download/v5.8.4/xz-5.8.4.tar.xz
"

# configure_cross [ARGS...]: the usual ./configure for a cross-built package.
configure_cross() {
    local guess
    for guess in build-aux/config.guess config.guess support/config.guess; do
        [ -f "$guess" ] && break
    done
    ./configure --prefix=/usr --host=$LFS_TGT --build="$(sh "$guess")" "$@"
}

# simple TARBALL [ARGS...]: unpack, configure, make, install into $LFS.
simple() {
    unpack "$1"
    shift
    configure_cross "$@"
    make
    make DESTDIR="$LFS" install
}

# ---- build steps -----------------------------------------------------------

build_m4() {
    simple m4-1.4.21.tar.xz
}

build_ncurses() {
    unpack ncurses-6.6.tar.gz
    # tic must run on the host while installing, so build a host copy first.
    mkdir build
    ( cd build && ../configure --prefix="$LFS/tools" AWK=gawk &&
      make -C include && make -C progs tic && install progs/tic "$LFS/tools/bin" )
    ./configure --prefix=/usr \
        --host=$LFS_TGT \
        --build="$(./config.guess)" \
        --mandir=/usr/share/man \
        --with-manpage-format=normal \
        --with-shared \
        --without-normal \
        --with-cxx-shared \
        --without-debug \
        --without-ada \
        --disable-stripping \
        AWK=gawk
    make
    make DESTDIR="$LFS" install
    ln -sf libncursesw.so "$LFS/usr/lib/libncurses.so"
    sed -e 's/^#if.*XOPEN.*$/#if 1/' -i "$LFS/usr/include/curses.h"
}

build_bash() {
    simple bash-5.3.tar.gz --without-bash-malloc
    ln -sf bash "$LFS/usr/bin/sh"
}

build_coreutils() {
    simple coreutils-9.12.tar.xz \
        --enable-install-program=hostname \
        --enable-no-install-program=kill,uptime
}

build_diffutils() {
    simple diffutils-3.12.tar.xz gl_cv_func_strcasecmp_works=y
}

build_file() {
    unpack file-5.48.tar.gz
    # The build runs `file` itself, so it needs a host copy of the same version.
    mkdir build
    ( cd build && ../configure --disable-bzlib --disable-libseccomp \
          --disable-xzlib --disable-zlib && make )
    configure_cross
    make FILE_COMPILE="$PWD/build/src/file"
    make DESTDIR="$LFS" install
    rm -f "$LFS/usr/lib/libmagic.la"
}

build_findutils() {
    simple findutils-4.11.0.tar.xz --localstatedir=/var/lib/locate
}

build_gawk() {
    unpack gawk-5.4.1.tar.xz
    sed -i 's/extras//' Makefile.in
    configure_cross
    make
    make DESTDIR="$LFS" install
}

build_grep()  { simple grep-3.12.tar.xz; }
build_gzip()  { simple gzip-1.15.tar.xz; }
build_make()  { simple make-4.4.1.tar.gz; }
build_patch() { simple patch-2.8.1.tar.xz; }
build_sed()   { simple sed-4.10.tar.xz; }
build_tar()   { simple tar-1.35.tar.xz; }

build_xz() {
    simple xz-5.8.4.tar.xz --disable-static --docdir=/usr/share/doc/xz-5.8.4
    rm -f "$LFS/usr/lib/liblzma.la"
}

build_binutils_pass2() {
    unpack binutils-$BINUTILS_VER.tar.xz
    # Stop libtool from linking the new libraries against the host's copies.
    local line=6031
    sed -n "${line}p" ltmain.sh | grep -q 'add_dir="$add_dir -L$inst_prefix_dir$libdir"' ||
        { echo "ltmain.sh changed; update the line number"; return 1; }
    sed -i "${line}s/\$add_dir//" ltmain.sh
    mkdir build && cd build
    ../configure --prefix=/usr \
        --build="$(../config.guess)" \
        --host=$LFS_TGT \
        --disable-nls \
        --enable-shared \
        --enable-gprofng=no \
        --disable-werror \
        --enable-64-bit-bfd \
        --enable-new-dtags \
        --enable-default-hash-style=gnu
    make
    make DESTDIR="$LFS" install
    rm -f "$LFS"/usr/lib/lib{bfd,ctf,ctf-nobfd,opcodes,sframe}.{a,la}
}

build_gcc_pass2() {
    unpack_gcc
    # Build libgcc and libstdc++ with POSIX threads support.
    sed '/thread_header =/s/@.*@/gthr-posix.h/' \
        -i libgcc/Makefile.in libstdc++-v3/include/Makefile.in
    mkdir build && cd build
    ../configure --build="$(../config.guess)" \
        --host=$LFS_TGT \
        --target=$LFS_TGT \
        LDFLAGS_FOR_TARGET=-L"$PWD/$LFS_TGT/libgcc" \
        --prefix=/usr \
        --with-build-sysroot="$LFS" \
        --enable-default-pie \
        --enable-default-ssp \
        --disable-nls \
        --disable-multilib \
        --disable-libatomic \
        --disable-libgomp \
        --disable-libquadmath \
        --disable-libsanitizer \
        --disable-libssp \
        --disable-libvtv \
        --enable-languages=c,c++
    make
    make DESTDIR="$LFS" install
    ln -sf gcc "$LFS/usr/bin/cc"
}

# ---- main ------------------------------------------------------------------

fetch_sources
for s in m4 ncurses bash coreutils diffutils file findutils gawk grep gzip \
         make patch sed tar xz binutils_pass2 gcc_pass2; do
    step "$s"
done
rm -rf "$BUILD"
echo "Stage 2 complete: temporary tools installed in $LFS/usr"
