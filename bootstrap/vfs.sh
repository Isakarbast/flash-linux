# vfs.sh: mount and unmount the kernel's virtual filesystems inside $LFS, so
# programs running in a chroot there see /dev, /proc, /sys and /run.
# Sourced by stage3.sh and enter.sh (as root).

mount_vfs() {
    mountpoint -q "$LFS/dev"     || mount --bind /dev "$LFS/dev"
    mountpoint -q "$LFS/dev/pts" || mount -t devpts devpts -o gid=5,mode=0620 "$LFS/dev/pts"
    mountpoint -q "$LFS/proc"    || mount -t proc proc "$LFS/proc"
    mountpoint -q "$LFS/sys"     || mount -t sysfs sysfs "$LFS/sys"
    mountpoint -q "$LFS/run"     || mount -t tmpfs tmpfs "$LFS/run"
    if [ -h "$LFS/dev/shm" ]; then
        install -d -m 1777 "$LFS$(realpath /dev/shm)"
    else
        mountpoint -q "$LFS/dev/shm" || mount -t tmpfs -o nosuid,nodev tmpfs "$LFS/dev/shm"
    fi
}

umount_vfs() {
    local m
    for m in dev/shm dev/pts dev sys proc run; do
        if mountpoint -q "$LFS/$m"; then
            umount "$LFS/$m" || umount -l "$LFS/$m"
        fi
    done
}
