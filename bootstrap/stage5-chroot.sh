#!/bin/bash
# stage5-chroot.sh: runs inside the new system (as root), started by stage5.sh.
#
# Installs the boot packages (kernel, firmware, eudev, OpenRC, GRUB, ...),
# writes this machine's settings (fstab, timezone, keymap, boot menu), installs
# GRUB on the EFI partition, and asks for the root password and a user.
#
# stage5.sh passes ROOT_UUID, ESP_UUID, TIMEZONE and KEYMAP in the environment.
set -euo pipefail
umask 022

PACKAGES="base-files cpio linux-firmware intel-ucode linux eudev openrc dhcpcd grub sudo"

die() { echo "stage5: $*" >&2; exit 1; }

echo "==> Installing fpm"
( cd /sources/fpm && make clean >/dev/null && make >/dev/null && install -m 755 fpm /usr/bin/fpm ) ||
    die "fpm failed to build"

for p in $PACKAGES; do
    echo "==> $p"
    start=$SECONDS
    fpm -y --overwrite install "$p" || die "$p failed (build logs: /var/cache/fpm/logs/$p.log)"
    echo "    $(( (SECONDS - start) / 60 ))m $(( (SECONDS - start) % 60 ))s"
done

echo "==> Writing this machine's settings"
# The EFI partition gets no fsck pass: there is no fsck.vfat on this system.
if ! grep -q '^UUID=' /etc/fstab 2>/dev/null; then
    cat > /etc/fstab <<EOF
# /etc/fstab: filesystems mounted at boot. See fstab(5).
# <filesystem>                             <dir>      <type> <options>                        <dump> <pass>
UUID=$ROOT_UUID  /          ext4   defaults,noatime                 0      1
UUID=$ESP_UUID                             /boot/efi  vfat   umask=0077                       0      0
tmpfs                                      /tmp       tmpfs  defaults,nosuid,nodev,mode=1777  0      0
EOF
fi
mkdir -p /boot/efi
ln -sfn "../usr/share/zoneinfo/$TIMEZONE" /etc/localtime
sed -i "s/^keymap=.*/keymap=\"$KEYMAP\"/" /etc/conf.d/keymaps

# Services: device manager at sysinit (from the eudev package), consoles and
# networking in the default runlevel.
rc-update add dhcpcd default >/dev/null

cat > /etc/default/grub <<'EOF'
GRUB_DEFAULT=0
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR="Freedom Linux"
GRUB_CMDLINE_LINUX_DEFAULT=""
GRUB_CMDLINE_LINUX=""
# No initramfs: the kernel can't look up root=UUID= by itself, but it can
# find the partition by its PARTUUID.
GRUB_DISABLE_LINUX_UUID=true
GRUB_DISABLE_LINUX_PARTUUID=false
GRUB_DISABLE_OS_PROBER=true
EOF
cat > /etc/grub.d/41_fedora <<EOF
#!/bin/sh
cat <<'MENU'
menuentry "Fedora" {
    insmod part_gpt
    insmod fat
    search --no-floppy --fs-uuid --set=root $ESP_UUID
    chainloader /EFI/systemd/systemd-bootx64.efi
}
MENU
EOF
chmod 755 /etc/grub.d/41_fedora

echo "==> Installing GRUB to /boot/efi/EFI/freedom"
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=freedom --no-nvram
grub-mkconfig -o /boot/grub/grub.cfg

# Passwords and a user account need a person at the keyboard.
if [ -t 0 ]; then
    case $(getent shadow root | cut -d: -f2) in
        ''|'*'|'!'|'!*'|x)
            echo "==> Set the root password"
            until passwd root; do :; done ;;
    esac
    if ! awk -F: '$3 >= 1000 && $3 < 65534 { found = 1 } END { exit !found }' /etc/passwd; then
        read -rp "==> Name for your user account: " user
        useradd -m -G wheel,audio,video,input,render,kvm,users -s /bin/bash "$user"
        echo "==> Set the password for $user"
        until passwd "$user"; do :; done
    fi
else
    echo "stage5: no terminal; set passwords later with: sudo ./enter.sh, then passwd" >&2
fi

echo "Stage 5 complete: the new system is bootable"
