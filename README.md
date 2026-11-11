# Flash Linux

A Linux distribution built from source: OpenRC + glibc, merged `/usr`, every
package built and managed by [fpm](https://github.com/Isakarbast/flash-package-manager)
(Flash Package Manager). Privacy first, minimal and fast, for daily use,
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
| dbus, elogind, polkit, mesa, Wayland, PipeWire, NetworkManager | done |
| KDE Plasma 6.7, Dolphin, kitty, Firefox, udisks2 | done, verified on real hardware |
| 32-bit libraries and mesa, Steam, proton-ge-custom | done, games run through Proton |
| Live ISO with a graphical installer (Calamares), offline | done, verified in a VM |
| More desktops in the installer: Xfce, Cinnamon, MATE, Hyprland, Sway, MangoWC | done, verified in a VM |

## Adding a package

`tools/new-recipe` writes a recipe from a download link:

```sh
tools/new-recipe https://github.com/htop-dev/htop/releases/download/3.5.3/htop-3.5.3.tar.xz
```

It downloads the source, pins its checksum and recognizes meson, CMake,
autotools, Cargo (pinning every crate in `Cargo.lock` so the build works
offline), Python and plain Makefiles. It writes `recipes/NAME/recipe` and
`build`, and lists the libraries the project asks for. Put the matching
recipe names in `depends`, then:

```sh
sudo fpm build NAME
```

For GitHub tag links (`.../archive/refs/tags/v1.2.tar.gz`) it names the file
`NAME-1.2.tar.gz` and fetches the description from GitHub. A second argument
sets the name; `--force` overwrites an existing recipe.

## License

GNU General Public License v3.0, see [LICENSE](LICENSE). This covers the
scripts and recipes in this repository; each packaged program keeps its own
license.
