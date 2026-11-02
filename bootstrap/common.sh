# common.sh: shared setup for the stage scripts. Source it after setting STAGE
# (e.g. STAGE=stage1) and SRC_LIST (the sources that stage needs).
#
# Environment: LFS (default /mnt/nvme0n1p1), SOURCES (default $LFS/sources).

LFS=${LFS:-/mnt/nvme0n1p1}
SOURCES=${SOURCES:-$LFS/sources}
LFS_TGT=x86_64-lfs-linux-gnu

# Toolchain versions shared by stage 1 and stage 2.
BINUTILS_VER=2.47
GCC_VER=16.2.0
GLIBC_VER=2.44

# file  sha256  url (checked against the upstream GPG signatures)
TOOLCHAIN_SRC="
binutils-$BINUTILS_VER.tar.xz 154ab23b60070e8f27013c22977f1129425d67d1e8acd6e13010e617811e4cff https://mirrors.kernel.org/gnu/binutils/binutils-$BINUTILS_VER.tar.xz
gcc-$GCC_VER.tar.xz   e6738e29597f733270731aa90600f37ffdc045079dfc27ec7e8192cc81085c3e  https://mirrors.kernel.org/gnu/gcc/gcc-$GCC_VER/gcc-$GCC_VER.tar.xz
gmp-6.3.0.tar.xz      a3c2b80201b89e68616f4ad30bc66aee4927c3ce50e33929ca819d5c43538898  https://mirrors.kernel.org/gnu/gmp/gmp-6.3.0.tar.xz
mpfr-4.2.2.tar.xz     b67ba0383ef7e8a8563734e2e889ef5ec3c3b898a01d00fa0a6869ad81c6ce01  https://mirrors.kernel.org/gnu/mpfr/mpfr-4.2.2.tar.xz
mpc-1.4.1.tar.xz      91204cd32f164bd3b7c992d4a6a8ce6519511aadab30f78b6982d0bf8d73e931  https://mirrors.kernel.org/gnu/mpc/mpc-1.4.1.tar.xz
"

die() { echo "$STAGE: $*" >&2; exit 1; }

[ "$(id -u)" -ne 0 ] || die "run this as your normal user, not root"

# Re-run in a clean environment so nothing from the host's shell setup leaks in.
if [ -z "${BOOTSTRAP_CLEAN:-}" ]; then
    exec env -i BOOTSTRAP_CLEAN=1 HOME="$HOME" TERM="${TERM:-dumb}" \
        LFS="$LFS" SOURCES="$SOURCES" /bin/bash --noprofile --norc "$0" "$@"
fi
set +h
umask 022
export LC_ALL=POSIX
export PATH=$LFS/tools/bin:/usr/bin
export CONFIG_SITE=$LFS/usr/share/config.site
export MAKEFLAGS=-j$(nproc)

for d in "$LFS/usr" "$LFS/etc" "$LFS/var" "$LFS/tools" "$SOURCES"; do
    [ -d "$d" ] && [ -w "$d" ] || die "$d must exist and be writable by $(id -un) (see README.md)"
done
for t in gcc g++ make bison gawk m4 makeinfo patch perl python3 xz tar curl sha256sum; do
    command -v "$t" >/dev/null || die "the host is missing $t"
done

STAMPS=$LFS/tools/.$STAGE
LOGS=$SOURCES/logs
BUILD=$SOURCES/build
mkdir -p "$STAMPS" "$LOGS"

# Download whatever in SRC_LIST is missing, checking each sha256.
fetch_sources() {
    echo "$SRC_LIST" | while read -r file sum url; do
        [ -n "$file" ] || continue
        if [ -f "$SOURCES/$file" ] && echo "$sum  $SOURCES/$file" | sha256sum -c --status; then
            continue
        fi
        echo "==> Downloading $file"
        curl -fL --retry 3 -o "$SOURCES/$file.part" "$url"
        echo "$sum  $SOURCES/$file.part" | sha256sum -c --status ||
            die "checksum mismatch for $file"
        mv "$SOURCES/$file.part" "$SOURCES/$file"
    done
}

# unpack TARBALL: extract into a fresh $BUILD and cd into the source dir.
unpack() {
    rm -rf "$BUILD"
    mkdir -p "$BUILD"
    tar -xf "$SOURCES/$1" -C "$BUILD"
    cd "$BUILD/${1%.tar.*}"
}

# Unpack gcc with gmp, mpfr and mpc inside it, and keep 64-bit libraries in lib.
unpack_gcc() {
    unpack gcc-$GCC_VER.tar.xz
    tar -xf "$SOURCES/mpfr-4.2.2.tar.xz" && mv mpfr-4.2.2 mpfr
    tar -xf "$SOURCES/gmp-6.3.0.tar.xz"  && mv gmp-6.3.0 gmp
    tar -xf "$SOURCES/mpc-1.4.1.tar.xz"  && mv mpc-1.4.1 mpc
    sed -e '/m64=/s/lib64/lib/' -i.orig gcc/config/i386/t-linux64
}

# step NAME: run build_NAME once, logging to $LOGS/NAME.log.
step() {
    [ -e "$STAMPS/$1" ] && { echo "==> $1 (already done)"; return; }
    echo "==> $1"
    local start=$SECONDS
    # In the background, so set -e still applies inside the build (an `if`
    # around the subshell would switch it off).
    ( "build_$1" ) >"$LOGS/$1.log" 2>&1 &
    if ! wait $!; then
        tail -n 30 "$LOGS/$1.log" >&2
        die "$1 failed; full log: $LOGS/$1.log"
    fi
    touch "$STAMPS/$1"
    echo "    done in $(( (SECONDS - start) / 60 ))m $(( (SECONDS - start) % 60 ))s"
}
