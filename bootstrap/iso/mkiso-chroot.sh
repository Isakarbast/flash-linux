#!/bin/bash
# mkiso-chroot.sh: runs inside the Flash Linux system (as root), started by
# build-iso.sh. Builds the live ISO in /var/tmp/iso:
#
#   repo/        every installed package plus the installer's, signed
#   live/        a live KDE system installed from that repository
#   iso/         boot files, live/rootfs.sfs (the live system) and repo/
#
# and writes /var/tmp/iso/flash-linux-$VERSION.iso.
set -euo pipefail
umask 022

VERSION=${VERSION:-2026.11}
LABEL=FLASH_LIVE
W=/var/tmp/iso
LIVE=$W/live
ISO=$W/iso
KEY=/etc/fpm/keys/flash-iso
CACHE=/var/cache/fpm/pkgs

die() { echo "mkiso: $*" >&2; exit 1; }
step() { echo "==> $*"; }

step "Installing fpm"
( cd /sources/fpm && make clean >/dev/null && make >/dev/null && install -m 755 fpm /usr/bin/fpm ) ||
    die "fpm failed to build"
# ...which then installs itself as a package, so it's in the repository and
# installed systems upgrade it like everything else.
fpm -y --overwrite install fpm

# The repository is made from the installed versions, so bring them up to date.
step "Upgrading the build system"
for _ in 1 2 3; do
    fpm -n upgrade | grep -q "Everything is up to date" && break
    fpm -y --overwrite upgrade
done
fpm -n upgrade | grep -q "Everything is up to date" || die "the build system could not be fully upgraded"

# Tools that make the ISO; the installer's packages are only built.
step "Installing the ISO tools"
fpm -y --overwrite install xorriso squashfs-tools mtools dosfstools efibootmgr
step "Building the installer and package groups"
# Calamares compiles against these ("fpm build" doesn't install them).
fpm -y --overwrite install kpmcore yaml-cpp
fpm -y build calamares flash-installer flash-base flash-kde flash-xfce flash-cinnamon flash-mate flash-hyprland flash-sway flash-mango flash-gaming
mkdir -p "$W"
for d in "$LIVE" "$ISO"; do
    [ ! -e "$d" ] || mv "$d" "$d.old.$$"
done
find "$W" -maxdepth 1 -name '*.old.*' -exec rm -rf {} +

# ---- repository: the installed version of every package, and the new ones
step "Collecting packages"
mkdir -p "$ISO/repo"
add() {
    local a=$CACHE/$1-$2.fpm.tar.zst
    [ -f "$a" ] || die "no archive for $1 $2 (run: fpm build $1)"
    ln -f "$a" "$ISO/repo/" 2>/dev/null || cp "$a" "$ISO/repo/"
}
installed=$(fpm list)
while read -r name ver; do add "$name" "$ver"; done <<<"$installed"
# Plus what the installer offers but this system doesn't have installed (the
# groups' members, e.g. firmware for other vendors' hardware).
groups="flash-base flash-kde flash-xfce flash-cinnamon flash-mate flash-hyprland flash-sway flash-mango flash-gaming"
members=$(for g in $groups; do sed -n 's/^depends *= *//p' "/var/db/fpm/recipes/main/$g/recipe"; done)
names=$(cut -d' ' -f1 <<<"$installed")
for p in calamares flash-installer $groups flatpak kpmcore yaml-cpp efivar nvidia lib32-nvidia $members; do
    grep -qxF "$p" <<<"$names" && continue
    a=$(ls -t "$CACHE/$p"-[0-9]*.fpm.tar.zst 2>/dev/null | head -1) || true
    if [ -z "$a" ]; then
        # Never built here (e.g. a renamed package): build it now.
        fpm -y build "$p" || die "$p failed to build"
        a=$(ls -t "$CACHE/$p"-[0-9]*.fpm.tar.zst 2>/dev/null | head -1) || true
    fi
    [ -n "$a" ] || die "no archive for $p"
    ln -f "$a" "$ISO/repo/" 2>/dev/null || cp "$a" "$ISO/repo/"
done
if [ ! -f "$KEY.key" ]; then
    step "Creating the repository signing key $KEY"
    mkdir -p "$(dirname "$KEY")"
    fpm keygen "$KEY"
fi
step "Indexing and signing the repository ($(ls "$ISO/repo" | wc -l) packages)"
fpm index "$ISO/repo" --sign "$KEY.key"

# ---- live system
step "Installing the live system"
mkdir -p "$LIVE"
cat > "$W/live.conf" <<EOF
usrmerge = yes
purge    = usr/share/info/dir *.la
prefer   = binary

[repo iso]
url = file://$ISO/repo
key = $KEY.pub
EOF
fpm --root "$LIVE" --config "$W/live.conf" sync
# Everything the installer can pick must come from the repository; a "build"
# line in the plan means a package (or a dependency) is missing from it.
plan=$(fpm --root "$LIVE" --config "$W/live.conf" -n install $groups nvidia lib32-nvidia)
missing=$(echo "$plan" | awk '$NF == "build" { print $1 }')
[ -z "$missing" ] || die "not in the ISO repository: $(echo $missing)"
fpm --root "$LIVE" --config "$W/live.conf" -y install flash-base flash-kde flash-installer nvidia
# Downloaded copies of the packages: the ISO carries them once, in repo/.
find "$LIVE/var/cache/fpm" -mindepth 1 -delete

step "Configuring the live system"
# The recipes (fpm comes with flash-base); the installer copies them into
# the installed system.
mkdir -p "$LIVE/var/db/fpm/recipes"
cp -r /var/db/fpm/recipes/main "$LIVE/var/db/fpm/recipes/main"
install -Dm644 "$KEY.pub" "$LIVE/etc/fpm/keys/flash-iso.pub"

echo flash-live > "$LIVE/etc/hostname"
printf '127.0.0.1 localhost\n::1 localhost\n127.0.1.1 flash-live\n' > "$LIVE/etc/hosts"
: > "$LIVE/etc/fstab"
chroot "$LIVE" /bin/bash -e <<'EOF'
useradd -m -G wheel,audio,video,input,render,users -s /bin/bash -c "Live user" live
passwd -d live >/dev/null
passwd -l root >/dev/null
for s in dbus elogind NetworkManager sddm; do rc-update add "$s" default >/dev/null; done
# The login screen owns tty1 (see stage7c).
rc-update del agetty.tty1 default >/dev/null
EOF
# The live user needs no passwords: sudo, polkit (Calamares runs through
# pkexec) and the login screen.
sed -i 's/^\(auth.*pam_unix\.so\)$/\1 nullok/' "$LIVE/etc/pam.d/system-auth"
echo 'live ALL=(ALL:ALL) NOPASSWD: ALL' > "$LIVE/etc/sudoers.d/live"
chmod 440 "$LIVE/etc/sudoers.d/live"
cat > "$LIVE/etc/polkit-1/rules.d/49-live.rules" <<'EOF'
polkit.addRule(function(action, subject) {
    if (subject.user == "live") return polkit.Result.YES;
});
EOF
mkdir -p "$LIVE/etc/sddm.conf.d"
printf '[Autologin]\nUser=live\nSession=plasma\n' > "$LIVE/etc/sddm.conf.d/autologin.conf"
d="$LIVE/home/live/Desktop"
mkdir -p "$d"
cp "$LIVE/usr/share/applications/calamares.desktop" "$d/install-flash-linux.desktop"
# Our name and logo, also in place of the translated ones.
sed -i '/^Name\[/d; /^Icon\[/d; s/^Name=.*/Name=Install Flash Linux/; s/^Icon=.*/Icon=flashlinux/' "$d/install-flash-linux.desktop"
chmod 755 "$d/install-flash-linux.desktop"
chroot "$LIVE" chown -R live:live /home/live
# NVIDIA's driver is on the live system but mustn't always win over nouveau:
# the initramfs blacklists one of them for the GPU it finds (iso/init). This
# copy of the driver's settings, minus its blacklist, takes the place of the
# package's.
grep -v '^blacklist' "$LIVE/usr/lib/modprobe.d/nvidia.conf" > "$LIVE/etc/modprobe.d/nvidia.conf"

# ---- initramfs
step "Making the initramfs"
kver=$(ls "$LIVE/usr/lib/modules" | sort -V | tail -1)
I=$W/initramfs
rm -rf "${I:?}"
mkdir -p "$I"/{usr/bin,usr/lib,proc,sys,dev,run,newroot}
ln -s usr/bin "$I/bin"
ln -s usr/bin "$I/sbin"
ln -s usr/lib "$I/lib"
ln -s usr/lib "$I/lib64"
for b in bash mount umount blkid switch_root losetup mkdir sleep cat seq insmod sed; do
    p=$(chroot "$LIVE" /bin/bash -c "command -v $b") || die "no $b in the live system"
    cp -L "$LIVE$p" "$I/usr/bin/$b"
    chroot "$LIVE" ldd "$p" | grep -o '/[^ ]*' | while read -r lib; do
        [ -e "$I$lib" ] || cp -L "$LIVE$lib" "$I/usr/lib/$(basename "$lib")"
    done
done
install -m 755 /sources/iso/init "$I/init"
# Modules for USB sticks and the live root, with their dependencies first.
mkdir -p "$I/usr/lib/modules"
chroot "$LIVE" modprobe -a --show-depends -S "$kver" loop usb-storage uas overlay isofs squashfs |
    awk '$1 == "insmod" { print $2 }' | awk '!seen[$0]++' | while read -r ko; do
        rel=${ko#/usr/lib/modules/}
        rel=${rel#/lib/modules/}
        mkdir -p "$I/usr/lib/modules/$(dirname "$rel")"
        cp "$LIVE$ko" "$I/usr/lib/modules/$rel"
        echo "$rel"
    done > "$I/usr/lib/modules/load.order"
( cd "$I" && find . | cpio -o -H newc --quiet | zstd -19 -q -T0 ) > "$W/initramfs.img"

# ---- ISO tree
step "Compressing the live system"
mkdir -p "$ISO/live" "$ISO/boot/grub" "$ISO/EFI/BOOT"
cp "$LIVE/boot/vmlinuz-$kver" "$ISO/boot/vmlinuz"
cp "$LIVE/boot/intel-ucode.img" "$ISO/boot/intel-ucode.img"
cp "$W/initramfs.img" "$ISO/boot/initramfs.img"
mksquashfs "$LIVE" "$ISO/live/rootfs.sfs" -comp zstd -Xcompression-level 15 -noappend -quiet

step "Making the UEFI boot loader"
install -m 644 /sources/iso/grub.cfg "$ISO/boot/grub/grub.cfg"
printf 'search --no-floppy --set=root --label %s\nset prefix=($root)/boot/grub\nconfigfile ($root)/boot/grub/grub.cfg\n' \
    "$LABEL" > "$W/grub-embed.cfg"
grub-mkstandalone -O x86_64-efi -o "$ISO/EFI/BOOT/BOOTX64.EFI" \
    --modules="part_gpt part_msdos iso9660 fat search search_label configfile linux all_video gfxterm" \
    "boot/grub/grub.cfg=$W/grub-embed.cfg"
# The same loader in a FAT image, which firmware boots from (El Torito and the
# appended EFI partition).
efi=$ISO/boot/efiboot.img
rm -f "$efi"
mkfs.fat -C -n FLASH_EFI "$efi" $(( $(du -k "$ISO/EFI/BOOT/BOOTX64.EFI" | cut -f1) + 1024 )) >/dev/null
mmd -i "$efi" ::/EFI ::/EFI/BOOT
mcopy -i "$efi" "$ISO/EFI/BOOT/BOOTX64.EFI" ::/EFI/BOOT/

step "Writing the ISO"
out=$W/flash-linux-$VERSION.iso
rm -f "$out"
xorriso -as mkisofs -iso-level 3 -full-iso9660-filenames -joliet -joliet-long -rational-rock \
    -volid "$LABEL" -appid "Flash Linux $VERSION" \
    -partition_offset 16 \
    -append_partition 2 C12A7328-F81F-11D2-BA4B-00A0C93EC93B "$efi" -appended_part_as_gpt \
    -eltorito-alt-boot -e --interval:appended_partition_2:all:: -no-emul-boot \
    -output "$out" "$ISO" 2>&1 | tail -3
echo
echo "ISO written: $out ($(du -h "$out" | cut -f1))"
