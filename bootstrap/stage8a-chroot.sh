#!/bin/bash
# stage8a-chroot.sh: runs inside the new system (as root), started by stage8a.sh.
#
# 32-bit (multilib) toolchain, the base for Steam and 32-bit games: glibc for
# i686 in /usr/lib32 (built with a throwaway multilib compiler), then gcc
# rebuilt with -m32 support, which adds lib32-gcc-libs and a meson cross file.
set -euo pipefail
umask 022

die() { echo "stage8a: $*" >&2; exit 1; }

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

install_each lib32-glibc gcc lib32-gcc-libs

echo "==> Checking 32-bit C and C++"
t=$(mktemp -d)
printf '#include <stdio.h>\nint main(void){printf("%%zu\\n", sizeof(void *));return 0;}\n' > "$t/a.c"
printf '#include <iostream>\nint main(){std::cout << sizeof(void *) << "\\n";}\n' > "$t/a.cc"
gcc -m32 -o "$t/c32" "$t/a.c" && [ "$("$t/c32")" = 4 ] || die "32-bit C compile failed"
g++ -m32 -o "$t/cc32" "$t/a.cc" && [ "$("$t/cc32")" = 4 ] || die "32-bit C++ compile failed"
gcc -o "$t/c64" "$t/a.c" && [ "$("$t/c64")" = 8 ] || die "64-bit C compile failed"
rm -r "$t"

echo
echo "Stage 8a complete: $(fpm list | wc -l) packages installed"
