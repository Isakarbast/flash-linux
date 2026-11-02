# Freedom Linux

A Linux distribution built from source: OpenRC + glibc, merged `/usr`, every
package built and managed by [fpm](https://github.com/Isakarbast/freedom-package-manager)
(Freedom Package Manager). Privacy first, minimal and fast, for daily use,
programming and gaming.

- [`bootstrap/`](bootstrap/README.md): stage scripts that build the system
  from a running Linux host, the way Linux From Scratch does, then hand it to
  fpm (toolchain, base system, kernel, boot, drivers).
- [`recipes/`](recipes/): fpm recipes, one directory per package (`recipe`
  metadata with pinned sha256 sources, a `build` script, optional
  `post-install`). The base system follows the Linux From Scratch book;
  packaging policy follows Arch where it matters (vendor-split firmware,
  drivers as optional packages).

## Status

| | |
|---|---|
| Toolchain (gcc 16.2, glibc 2.44, binutils 2.47) and 70-package base system | done |
| Boot: generic kernel 7.3.1, eudev, OpenRC as init, GRUB (UEFI), dhcpcd, sudo | done, boots on real hardware |
| linux-firmware split by vendor, NVIDIA driver as an fpm package | done, verified (RTX 3060) |
| dbus, elogind, polkit, mesa, Wayland, PipeWire, NetworkManager | next |
| KDE Plasma, Dolphin, kitty, Firefox | planned |
| 32-bit libraries, Steam, proton-ge-custom | planned |
| Installer and ISO | planned |

## License

GNU General Public License v3.0, see [LICENSE](LICENSE). This covers the
scripts and recipes in this repository; each packaged program keeps its own
license.
