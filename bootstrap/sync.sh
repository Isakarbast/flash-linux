# sync.sh: copy the recipes and fpm into the new system and download every
# source into fpm's cache (the chroot has no network). Sourced by stage4.sh
# and stage5.sh (as root) after setting LFS, HERE, FPM_SRC and RECIPES.

sync_recipes() {
    echo "==> Copying recipes and fpm into the new system"
    rm -rf "$LFS/var/db/fpm/recipes/main"
    mkdir -p "$LFS/var/db/fpm/recipes" "$LFS/var/cache/fpm/sources"
    cp -r "$RECIPES" "$LFS/var/db/fpm/recipes/main"
    rm -rf "$LFS/sources/fpm"
    mkdir -p "$LFS/sources/fpm"
    tar -C "$FPM_SRC" --exclude=.git --exclude='*.o' --exclude=./fpm -cf - . | tar -xf - -C "$LFS/sources/fpm"
    # The fpm recipe's source: its release tarball, made here because the
    # repository is private (as the user who owns the checkout, for git).
    local as=()
    [ -z "${SUDO_USER:-}" ] || as=(runuser -u "$SUDO_USER" --)
    "${as[@]}" make -s -C "$FPM_SRC" dist
    mv "$FPM_SRC"/fpm-*.tar.gz "$LFS/var/cache/fpm/sources/"
    # The same for Flash's own apps, when their checkout sits next to fpm's.
    local apps=${FLASH_APPS_SRC:-$(dirname "$FPM_SRC")/flash-apps}
    if [ -f "$apps/Makefile" ]; then
        "${as[@]}" make -s -C "$apps" dist
        mv "$apps"/flash-apps-*.tar.gz "$LFS/var/cache/fpm/sources/"
    fi
}

# Every remote source of every recipe. Tarballs from the earlier stages, or in
# $SOURCE_CACHE, are copied instead of downloaded again.
fetch_sources() {
    local cache=$LFS/var/cache/fpm/sources r srcs sums url sum file dest dir found
    echo "==> Fetching sources"
    for r in "$RECIPES"/*/recipe; do
        srcs=$(sed -n 's/^source *= *//p' "$r")
        sums=$(sed -n 's/^sha256 *= *//p' "$r")
        set -- $sums
        for url in $srcs; do
            sum=$1
            shift
            case $url in *://*) ;; *) continue ;; esac
            # "name::url" downloads url under another file name.
            case $url in
                *::*) file=${url%%::*}; url=${url#*::} ;;
                *) file=${url##*/} ;;
            esac
            dest=$cache/$file
            if [ -f "$dest" ] && echo "$sum  $dest" | sha256sum -c --status; then
                continue
            fi
            found=
            for dir in "$LFS/sources" ${SOURCE_CACHE:+"$SOURCE_CACHE"}; do
                if [ -f "$dir/$file" ] && echo "$sum  $dir/$file" | sha256sum -c --status; then
                    cp "$dir/$file" "$dest"
                    found=1
                    break
                fi
            done
            [ -z "$found" ] || continue
            echo "    $file"
            curl -fsSL --retry 3 --connect-timeout 30 -o "$dest.part" "$url"
            echo "$sum  $dest.part" | sha256sum -c --status || die "checksum mismatch for $file"
            mv "$dest.part" "$dest"
        done
    done
}
