# Bootstrap

Builds the new system on `/mnt/nvme0n1p1` from the running Fedora system, the
way Linux From Scratch does.

| Stage | What | Status |
|---|---|---|
| 1 | Temporary cross toolchain: binutils, gcc, Linux headers, glibc, libstdc++ | `stage1.sh` |
| 2 | Temporary tools: m4, ncurses, bash, coreutils, diffutils, file, findutils, gawk, grep, gzip, make, patch, sed, tar, xz, then binutils and gcc again | `stage2.sh` |
| 3 | Chroot in: essential files, gettext, bison, perl, Python, texinfo, util-linux, zstd, fpm; remove /tools | `stage3.sh` |
| 4 | The base system as fpm packages (70 recipes in `../recipes`) | `stage4.sh` |
| 5 | Boot: kernel, firmware, eudev, OpenRC (as init), GRUB, dhcpcd, sudo, machine settings | `stage5.sh` |
| 6a | Generic kernel + linux-devel, linux-firmware split by vendor, X client libraries, libglvnd, NVIDIA driver | `stage6a.sh` |
| 6b-d | dbus, elogind, polkit, glib, libinput, fonts; LLVM, mesa, Wayland; PipeWire, NetworkManager | next |
| 7 | KDE Plasma, Dolphin, kitty, Firefox | |
| 8 | 32-bit libraries, Steam, proton-ge-custom | |

## Stage 1

Versions: binutils 2.47, gcc 16.2.0 (with gmp 6.3.0, mpfr 4.2.2, mpc 1.4.1),
glibc 2.44, Linux 7.3.1 headers. Every tarball is pinned by sha256; the hashes
were taken from files whose GNU / kernel.org GPG signatures verified.

```sh
sudo mkdir -p /mnt/nvme0n1p1/{tools,sources}
sudo chown -R "$USER": /mnt/nvme0n1p1/{usr,etc,var,tools,sources}
./stage1.sh
```

- Runs as your normal user, never root, in a clean environment (`env -i`).
- Each step logs to `/mnt/nvme0n1p1/sources/logs/<step>.log`; a failure shows the
  end of the log. Running it again skips finished steps.
- The ownership change is temporary: stage 3 gives everything back to root.

## Stage 2

```sh
./stage2.sh
```

Same rules as stage 1 (normal user, logs, resumes). Takes about 15 minutes,
most of it gcc. Afterwards the partition has its own shell, coreutils, make,
compiler and so on, enough to chroot into it.

## Stage 3

```sh
sudo ./stage3.sh
```

Downloads the sources, gives the partition back to root, mounts `/dev`,
`/proc`, `/sys` and `/run`, then chroots in and runs `stage3-chroot.sh`
(logs in `/mnt/nvme0n1p1/sources/logs`). Mounts are undone on exit, even after
a failure. At the end the cross toolchain in `/tools` is deleted, and fpm is
installed in the new system.

Afterwards, `sudo ./enter.sh` opens a root shell inside the new system.

## Stage 4

```sh
sudo ./stage4.sh
```

Copies the recipes from `../recipes` and a fresh fpm into the new system,
downloads every source into `/var/cache/fpm/sources` (pass
`SOURCE_CACHE=dir` to reuse tarballs you already have), then chroots in and
runs `stage4-chroot.sh`: it writes `/etc/fpm.conf` and installs the 70 base
packages with `fpm --overwrite install`, in Linux From Scratch chapter 8
order. Each package replaces the temporary tool it supersedes. Build logs are
in `/var/cache/fpm/logs`. Installed packages are skipped on a rerun.

Afterwards everything except the directory layout, the generated locale
archive and `/usr/bin/fpm` itself belongs to a package (`fpm list`,
`fpm owner FILE`, `fpm check`).

## Stage 5

```sh
sudo SOURCE_CACHE=$HOME/.cache/distro-sources ./stage5.sh
```

Installs linux 7.3.1 (NVMe and ext4 built in, so no initramfs; stage 6a
replaces it with the generic kernel), linux-firmware,
Intel microcode, eudev, OpenRC as PID 1 (`-Dsysvinit=true`: openrc-init,
reboot/poweroff, agetty on tty1-6), dhcpcd, GRUB and sudo. Then it writes
fstab, timezone and keymap (taken from Fedora), installs GRUB to
`/boot/efi/EFI/freedom` with a Fedora entry in its menu, asks for the root
password and a user (in group wheel for sudo), and adds a "Freedom Linux"
firmware boot entry that is used for the next boot only.

Networking at first boot is wired (dhcpcd); Wi-Fi comes with NetworkManager
in the desktop stages. The screen uses the firmware framebuffer until the
NVIDIA driver is installed (stage 6).

## Stage 6a

```sh
sudo mount /dev/nvme0n1p1 /mnt/nvme0n1p1
sudo SOURCE_CACHE=$HOME/.cache/distro-sources ./stage6a.sh
```

- **Kernel**: Fedora's full config, every driver as a module (the same kernel
  runs on any PC; eudev loads only what the hardware needs). `linux-devel`
  holds the build files for out-of-tree modules, like Arch's linux-headers.
- **Firmware**: `linux-firmware` keeps the shared files; vendor firmware is in
  `linux-firmware-{amdgpu,radeon,intel,nvidia,realtek,mediatek,atheros,broadcom,qcom,cirrus,mellanox,netronome}`.
  The script installs the ones matching this PC's PCI devices.
- **NVIDIA** (only if an NVIDIA GPU is found): driver 615.78.08 as an fpm
  package (`fpm install nvidia`), open kernel modules built against
  `linux-devel`, nouveau blacklisted, modesetting on. It needs libglvnd and the
  X client libraries, which are installed first. After a kernel update,
  rebuild it with `fpm --rebuild install nvidia`.
