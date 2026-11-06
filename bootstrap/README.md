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
| 7e | udisks2 and its storage stack (drives in Dolphin) | `stage7e.sh` |
| 8a | 32-bit toolchain: lib32 glibc, gcc rebuilt with multilib (+ lib32-gcc-libs) | `stage8a.sh` |
| 8b | 32-bit libraries and NVIDIA driver, Steam, Proton-GE | `stage8b.sh` |
| 8c | 32-bit mesa (AMD and Intel graphics for 32-bit games) with a 32-bit LLVM | `stage8c.sh` |
| 9b | X.Org server, LightDM, Xfce 4.20 (and Rust + librsvg, VTE, gvfs, nm-applet, polkit agent) | `stage9b.sh` |
| 9c | wlroots 0.20, Sway, MangoWC, Waybar, fuzzel, mako, portals | `stage9c.sh` |
| 9d | Hyprland and the hyprwm libraries, hyprlock, hypridle, its portal | `stage9d.sh` |
| 9e | MATE 1.28 (and libsoup 3, itstool) | `stage9e.sh` |
| 9f | GObject Introspection data for the GTK stack, PyGObject, SpiderMonkey 128 + cjs, tray icons | `stage9f.sh` |
| 9g | Cinnamon 6.6 with Muffin, Nemo and the X-Apps | `stage9g.sh` |
| 10a | Flatpak with Flathub (apps without a recipe each), GnuPG, OSTree | `stage10a.sh` |
| ISO | Live system and graphical installer (Calamares) with every package on it | `build-iso.sh` |

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
`/boot/efi/EFI/flash` with a Fedora entry in its menu, asks for the root
password and a user (in group wheel for sudo), and adds a "Flash Linux"
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
build as a local module proxy. `flash-kde-settings` holds the system-wide
KDE defaults in `/etc/xdg`: kitty as Plasma's terminal, and Plasma starting
with an empty session instead of reopening the last one's apps (each user can
change both in System Settings).

Firefox is Mozilla's signed official build, installed to `/usr/lib/firefox`
with a policy that turns off its own updater (fpm updates it), telemetry and
studies. It runs on GTK 3, which brings fribidi, cairo, pango, at-spi2-core,
hicolor-icon-theme and gsettings-desktop-schemas; `/etc/gtk-3.0/settings.ini`
uses the Breeze icons and cursors. RTKit lets PipeWire use realtime priority.
glib is rebuilt (release 2) to ship hooks that recompile GSettings schemas and
the GIO module cache; gtk3 ships hooks for icon caches and input methods.

## Stage 7e

```sh
sudo SOURCE_CACHE=$HOME/.cache/distro-sources ./stage7e.sh
```

udisks2, the service Plasma and Dolphin use to list and mount drives (started
on demand over D-Bus; mounting asks for an admin password through polkit). It
brings libblockdev 3.5 with the plugins udisks loads (partitions, filesystems,
swap, loop, RAID, encryption, NVMe, SMART) and what those need: LVM2 (for the
device-mapper library; its systemd activation rule is removed), cryptsetup,
keyutils, popt, libaio, libatasmart, libbytesize and libnvme.

## Stage 8a

```sh
sudo SOURCE_CACHE=$HOME/.cache/distro-sources ./stage8a.sh
```

The 32-bit (multilib) toolchain, laid out as on Arch: 32-bit libraries in
`/usr/lib32`, `/usr/lib/ld-linux.so.2` pointing at its loader. The system gcc
can't target 32-bit yet, and gcc's 32-bit libraries need a 32-bit glibc
first, so `lib32-glibc` builds a throwaway C compiler with `-m32` support
(static libgcc only, like LFS's first-pass gcc) and builds glibc 2.44 for
i686 with it; only `/usr/lib32`, `gnu/stubs-32.h` and `gnu/lib-names-32.h`
are installed. gcc is then rebuilt (release 2) with `--enable-multilib`; its
32-bit runtime libraries go to the `lib32-gcc-libs` subpackage, and it ships
`/usr/share/meson/cross/lib32`, the cross file the lib32 meson builds use.
The stage ends by compiling and running 32- and 64-bit C and C++ programs.

## Stage 8b

```sh
sudo SOURCE_CACHE=$HOME/.cache/distro-sources ./stage8b.sh
```

The 32-bit libraries Steam and 32-bit games take from the system, each built
from the same tarball as its 64-bit package and installing only `/usr/lib32`:
libffi, the X11/XCB client libraries, libdrm, Wayland, libglvnd, the Vulkan
loader, libudev (from eudev), alsa-lib and libxcrypt (with Steam's
`libcrypt.so.1`). `lib32-nvidia` is the 32-bit half of the NVIDIA driver from
the same `.run` file (OpenGL/EGL/GLES, Vulkan, CUDA, NVENC/NVDEC, VDPAU);
32-bit mesa, for AMD and Intel GPUs, comes in stage 8c.

`steam` is Valve's launcher (its tarball matches Valve's signed `.dsc` and
Arch's checksum); it downloads the Steam client and runtime into
`~/.local/share/Steam` on first start. Its controller and VR udev rules also
give the devices to the `input` group, since eudev has no `uaccess`.
`proton-ge-custom` (GE-Proton11-12, checked against its published SHA-512)
goes to `/usr/share/steam/compatibilitytools.d`, where Steam lists it as a
compatibility tool.

## Stage 8c

```sh
sudo SOURCE_CACHE=$HOME/.cache/distro-sources ./stage8c.sh
```

32-bit mesa, so 32-bit games also run on AMD and Intel GPUs. It needs 32-bit
builds of LLVM (only the X86 and AMDGPU targets; `llvm-config32` is the real
32-bit binary, installed in `/usr/bin` so it reports the right paths),
zlib, expat, zstd, libelf, libpciaccess and libdrm (with Intel support).
mesa is rebuilt (release 2) to also install its OpenCL C and precompiler
tools, which the 32-bit build runs instead of building its own. The 32-bit
Vulkan drivers' `*.i686.json` files sit next to the 64-bit ones in
`/usr/share/vulkan/icd.d`.

## Stages 9b to 9g: more desktops

```sh
sudo SOURCE_CACHE=$HOME/.cache/distro-sources ./stage9b.sh   # then 9c to 9g
```

The desktops the installer offers besides KDE Plasma, each as a package group
(`flash-xfce`, `flash-cinnamon`, `flash-mate`, `flash-hyprland`, `flash-sway`,
`flash-mango`)
that `fpm install` adds to an existing system too. They log in through
**LightDM** with its GTK greeter (the session list shows every installed
desktop); KDE keeps SDDM. `lightdm-session` starts each session with the login
environment and its own D-Bus session bus. Cinnamon gets the Flash logo on its
menu button and the Flash wallpaper (from `flash-branding`). Nothing is switched over on a
running system: SDDM stays the login screen, and the new sessions appear in
its list.

- **9b** brings the X.Org server (Xorg, with NVIDIA's X driver added to the
  `nvidia` package) and the X session tools, LightDM, and Xfce 4.20 with
  Thunar, xfce4-terminal, Mousepad, Ristretto and the panel plugins. Also
  shared by the other GTK desktops: Rust (official binaries) and librsvg, which
  draws the SVG icons GTK themes use (its Rust crates are pinned one by one
  from its `Cargo.lock`), VTE, dconf, gvfs (trash and USB drives in file
  managers), nm-applet, polkit-gnome and the Adwaita icons.
- **9c** brings wlroots 0.20 with Sway and MangoWC (with scenefx), Waybar
  (with gtkmm 3), fuzzel, mako, swaylock/swayidle, grim/slurp, wl-clipboard
  and the wlr and GTK portals. Their default configs use kitty and fuzzel and
  start sound (PipeWire), the bar, notifications, nm-applet and the polkit
  agent, since tiling compositors don't run XDG autostart.
- **9d** brings Hyprland 0.57 (configured in Lua) and the hyprwm libraries it
  is built from, hyprlock, hypridle and its screen-sharing portal. New users
  get Hyprland's example config with the same defaults, from `/etc/skel`.
- **9e** brings MATE 1.28: Marco, Caja, the panel, control center, settings
  daemon, screen locker, power manager, volume control, terminal and system
  monitor, with the Menta themes and icons. libxml2 is rebuilt with its Python
  module for itstool (MATE's help pages), and libmateweather is ported to
  libsoup 3 (Arch's patch). zenity 3.44 (the last GTK 3 release) gives Marco
  its dialogs.

- **9f** prepares Cinnamon, whose shell is JavaScript (cjs, on SpiderMonkey
  128) and whose settings are Python: GObject Introspection, then GLib, GTK,
  Pango, NetworkManager, polkit, upower and the other libraries they reach
  rebuilt with their introspection data (GObject Introspection and GLib need
  each other, so it goes GI, GLib, GI again), PyGObject, pycairo, dbus-python,
  cbindgen and SpiderMonkey (patched for Rust 1.99 and Python 3.15). Also the
  Ayatana AppIndicator libraries, so nm-applet shows up in Waybar's tray, and
  Waybar again with libdbusmenu so tray icons have their right-click menus.
- **9g** brings Cinnamon 6.6: Muffin, the Cinnamon shell, its session manager,
  settings daemon, control center, screensaver and Nemo, Linux Mint's X-Apps
  library, gcr, libtimezonemap (the map in Date & Time; Debian's libsoup 3
  port, with its online city search switched off), and the Python modules its tools use (pure-Python ones from
  their wheels, installed with Python's bundled pip; the others built from
  source).
- **10a** adds Flatpak, so desktop apps (Discord, Spotify, OBS, ...) install
  from Flathub with `flatpak install flathub APP` instead of needing a recipe
  each. GnuPG checks Flathub's signatures, OSTree stores the apps and AppStream
  reads their metadata; Flathub is added when Flatpak is installed. It only
  needs a base system, so it also runs on a system installed from the ISO.

## The ISO

```sh
sudo SOURCE_CACHE=$HOME/.cache/distro-sources ./build-iso.sh
```

Builds `flash-linux-2026.11.iso` (about 8.6 GB, so a 16 GB or bigger USB
stick) in your home directory, using the Flash Linux partition as the build
machine. It runs `iso/mkiso-chroot.sh` in the chroot, which:

1. Installs the current fpm, as the `fpm` package (the source tarball comes
   from `make dist` in fpm's checkout), and upgrades every installed package,
   so the ISO carries what the recipes say. This rebuilds whatever changed.
2. Builds Calamares and the installer's packages: `flash-installer` (its
   settings, branding and two job modules) and the package groups the
   installer offers, `flash-base`, `flash-kde` and `flash-gaming`.
3. Puts every installed package, plus every member of those groups (e.g.
   firmware for hardware this machine doesn't have), into a repository,
   signs it with `/etc/fpm/keys/flash-iso.key` (made on the first run), and
   checks that everything the installer can pick installs from it: the build
   stops if a package would have to be built from source.
4. Installs the live system from that repository (`flash-base`,
   `flash-kde`, `nvidia` and the installer): user `live` without a
   password, logged in automatically, with an "Install Flash Linux" icon on
   the desktop.
5. Makes a small initramfs (bash, util-linux, the USB, CD, loop, squashfs and
   overlay modules) that finds the medium by its label, mounts the compressed
   live system with a RAM overlay and starts OpenRC. Installed systems need no
   initramfs. It also picks the graphics driver: an NVIDIA GPU of the GTX 16 /
   RTX 20 series or newer (PCI device 0x1e00 and up) gets NVIDIA's driver,
   and the installer then suggests it; anything else gets mesa. Without this
   an RTX card would run Plasma on the CPU (llvmpipe), since mesa's nouveau
   driver has no 3D support for it.
6. Writes a UEFI-only hybrid image: GRUB with live and safe-graphics
   (`nomodeset`) entries, booting from a USB stick or DVD.

The installer asks for the language, time zone, keyboard, desktop (KDE
Plasma, Xfce, Cinnamon, MATE, Hyprland, Sway, MangoWC or none), graphics driver (Mesa or NVIDIA), extras (gaming), disk and
user. It installs from the repository on the medium with fpm; nothing is
downloaded. It then copies the recipes, sets the console keymap, gives tty1
to the login screen, installs GRUB to the EFI partition (in `EFI/flash`, plus
the fallback `EFI/BOOT/BOOTX64.EFI` when no other system has one there, so
the disk still boots if the firmware drops the boot entry) and writes
`/etc/default/grub` to boot by `root=PARTUUID`. Disk encryption isn't
offered: it needs an initramfs.

Write the ISO to a USB stick (everything on it is erased; check the device
name with `lsblk`):

```sh
sudo dd if=flash-linux-2026.11.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

