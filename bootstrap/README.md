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
| 6b | PAM (shadow, sudo rebuilt with it), curl + CA certificates, glib, D-Bus, elogind, polkit, libinput, fonts | `stage6b.sh` |
| 6c | X client libraries, Wayland, xkb, libdrm, Vulkan loader, SPIR-V tools, LLVM + clang, mesa; NVIDIA's Wayland/GBM libraries | `stage6c.sh` |
| 6d | ALSA, PipeWire (+ pulse/alsa/jack), WirePlumber, NetworkManager + wpa_supplicant | `stage6d.sh` |
| 7a | Qt 6.12 (+ ICU, image libraries, XCB utilities, FFmpeg with dav1d and NVIDIA decode); sqlite rebuilt with its soname | `stage7a.sh` |
| 7b | KDE Frameworks 6.29 (69 packages) + dependencies (ECM, icons, DocBook, polkit-qt, qca, Aspell, ...) | `stage7b.sh` |
| 7c | Plasma 6.7 core desktop, Xwayland, SDDM (Wayland greeter), portals, CUPS (Qt rebuilt with it) | `stage7c.sh` |
| 7d | Dolphin, kitty (with Go), Firefox (official binary, on GTK 3), RTKit | `stage7d.sh` |
| 8 | 32-bit libraries, Steam, proton-ge-custom | next |

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

## Stage 6b

```sh
sudo SOURCE_CACHE=$HOME/.cache/distro-sources ./stage6b.sh
```

- **Linux-PAM**, with shadow and sudo rebuilt to use it. Each package ships its
  own `/etc/pam.d` files (BLFS configuration: `system-auth`, `system-account`,
  `system-session`, `system-password`, and `other` denying anything unknown),
  so logins keep working at every step.
- **curl** and Mozilla's CA certificates, so fpm can download inside the system.
- **glib, D-Bus, elogind, polkit**: dbus and elogind are OpenRC services in the
  default runlevel; polkit is started by D-Bus when needed.
- **libinput** (with mtdev and libevdev) and the font stack: libpng,
  freetype, fontconfig (a hook refreshes the font cache), harfbuzz, DejaVu.

## Stage 6c

```sh
sudo SOURCE_CACHE=$HOME/.cache/distro-sources ./stage6c.sh
```

The graphics stack, 46 packages following BLFS: cmake, the X client
libraries, Wayland and wayland-protocols, xkeyboard-config and libxkbcommon,
libdrm, Vulkan headers and loader, SPIR-V tools, glslang, LLVM 23 with clang
(about 40 minutes), SPIRV-LLVM-Translator, and mesa 26.2.3 with drivers for
AMD (radeonsi, RADV), Intel (iris, crocus, ANV), nouveau, llvmpipe/lavapipe
and zink. mesa is built for libglvnd, so it sits next to the NVIDIA driver;
if that is installed, it is upgraded with its EGL platform libraries for
Wayland, GBM, XCB and Xlib (what KWin and XWayland use on NVIDIA).

## Stage 6d

```sh
sudo SOURCE_CACHE=$HOME/.cache/distro-sources ./stage6d.sh
```

- **Sound**: alsa-lib (with alsa-ucm-conf), alsa-utils, PipeWire 1.6 with
  `pipewire-pulse`, `pipewire-alsa` and `pipewire-jack`, and WirePlumber. With
  no systemd user session, `/etc/xdg/autostart/pipewire.desktop` runs
  `pipewire-launcher` at desktop login (like Gentoo's launcher). ALSA programs
  go through PipeWire (`/etc/alsa/conf.d`).
- **Networking**: NetworkManager 1.58 (gnutls, internal DHCP, keyfile
  connections) with wpa_supplicant for Wi-Fi, started over D-Bus. It replaces
  dhcpcd in the default runlevel.
- **Privacy defaults** (`/usr/lib/NetworkManager/conf.d/50-privacy.conf`,
  override in `/etc/NetworkManager/conf.d/`): random MAC while scanning and
  per Wi-Fi connection, a stable per-network MAC on Ethernet, IPv6 privacy
  addresses, no connectivity check, no mDNS/LLMNR.

## Stage 7a

```sh
sudo SOURCE_CACHE=$HOME/.cache/distro-sources ./stage7a.sh
```

Qt 6.12 as one package (`qt-everywhere`, without QtWebEngine), laid out like
Arch: libraries in `/usr/lib`, tools in `/usr/lib/qt6/bin` with `*6` links in
`/usr/bin`, plugins in `/usr/lib/qt6/plugins`. Before it: sqlite is rebuilt
with `--soname=legacy` (its autosetup build otherwise sets no SONAME, and Qt
would record it by path), then nasm, double-conversion, ICU, libjpeg-turbo,
libwebp, libtiff, the XCB utilities, dav1d, NVIDIA's codec headers and FFmpeg
(Qt Multimedia's backend; also used by Firefox). Qt takes about 40 minutes.

## Stage 7b

```sh
sudo SOURCE_CACHE=$HOME/.cache/distro-sources ./stage7b.sh
```

KDE Frameworks 6.29, one fpm package per framework (as Arch packages them),
in BLFS build order and installed under `/usr` (libexec in `/usr/lib`). Not
built: `kapidox` (documentation tooling) and `modemmanager-qt` (no ModemManager).
Dependencies first: extra-cmake-modules, plasma-wayland-protocols, Breeze and
Oxygen icons, DocBook XML/XSL (registered in `/etc/xml/catalog` by their
post-install scripts), libxslt, perl URI (for kdoctools), libgcrypt and
libsecret (KWallet), polkit-qt and qca (admin prompts), libcanberra with
Vorbis (notification sounds), lmdb (Baloo), libical, shared-mime-info (a hook
updates the MIME database), barcode libraries, `which`, and Aspell with its
English dictionary (Sonnet needs a spelling backend).

## Stage 7c

```sh
sudo SOURCE_CACHE=$HOME/.cache/distro-sources ./stage7c.sh
```

The core of KDE Plasma 6.7.4 (KWin, plasma-workspace, plasma-desktop, System
Settings, lock screen, network/volume/power applets, kscreen, polkit agent,
KWallet PAM unlock, Breeze, portals, kinfocenter); BLFS's mobile, TV, printer,
Bluetooth, GTK-theming and Discover parts are left out. Dependencies include
Xwayland, upower, accountsservice, xdg-desktop-portal (with GStreamer),
libva, lm-sensors, libwacom, a minimal ModemManager (plasma-nm requires it)
and CUPS; Qt is rebuilt (release 2) with CUPS support, which the portal's
print dialog needs. plasma-desktop is built without its X11 mouse/touchpad
pages (there is no X.org server, only Xwayland).

SDDM shows the login screen on KWin under Wayland
(`/usr/lib/sddm/sddm.conf.d/10-wayland.conf`, Breeze theme) and is enabled at
boot; text logins remain on tty2-6 (Ctrl+Alt+F2). The CUPS print server is
installed but not started (`rc-update add cupsd default` to print).
Once bubblewrap is installed, fpm builds run sandboxed (read-only system, no
network). Fedora mounts `/` as shared, which bubblewrap can't work under, so
from this stage on the host scripts (and `enter.sh`) enter the chroot in a
private mount namespace.

## Stage 7d

```sh
sudo SOURCE_CACHE=$HOME/.cache/distro-sources ./stage7d.sh
```

The everyday apps. Dolphin 26.08 with baloo-widgets (information panel),
kio-extras (sftp via libssh, phones via libmtp, man pages, recent files; built
without libproxy's WPAD detection) and ffmpegthumbs (video thumbnails).
kitty 0.50, built from source with the official Go 1.27 binary (packaged as
`go`, with `GOTOOLCHAIN=local` so it never downloads other toolchains) and
the official Slang shader compiler binary (`shader-slang`, kept in
`/usr/lib/shader-slang` with `/usr/bin/slangc`); it bundles the Nerd Fonts
symbols font. Its Go
modules are downloaded from proxy.golang.org beforehand (as `name::url`
sources, also checked against kitty's `go.sum`) and served to the offline
build as a local module proxy. kitty is set as Plasma's terminal in
`/etc/xdg/kdeglobals`.

Firefox is Mozilla's signed official build, installed to `/usr/lib/firefox`
with a policy that turns off its own updater (fpm updates it), telemetry and
studies. It runs on GTK 3, which brings fribidi, cairo, pango, at-spi2-core,
hicolor-icon-theme and gsettings-desktop-schemas; `/etc/gtk-3.0/settings.ini`
uses the Breeze icons and cursors. RTKit lets PipeWire use realtime priority.
glib is rebuilt (release 2) to ship hooks that recompile GSettings schemas and
the GIO module cache; gtk3 ships hooks for icon caches and input methods.
