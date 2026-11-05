#!/usr/bin/env python3
# Calamares job: the Flash Linux settings the stage scripts write by hand on
# a bootstrapped system: fpm's recipes (so the installed system can build
# from source), the console keymap for OpenRC, a login screen on tty1, and GRUB's
# defaults (no initramfs, so the kernel finds root= by PARTUUID).

import os
import shutil

import libcalamares

GRUB_DEFAULTS = """GRUB_DEFAULT=0
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR="Flash Linux"
GRUB_CMDLINE_LINUX_DEFAULT=""
GRUB_CMDLINE_LINUX=""
# No initramfs: the kernel can't look up root=UUID= by itself, but it can
# find the partition by its PARTUUID.
GRUB_DISABLE_LINUX_UUID=true
GRUB_DISABLE_LINUX_PARTUUID=false
GRUB_DISABLE_OS_PROBER=true
"""


def pretty_name():
    return "Configuring Flash Linux"


def target(root, path):
    return os.path.join(root, path.lstrip("/"))


def run():
    root = libcalamares.globalstorage.value("rootMountPoint")

    # The recipes fpm builds from (fpm itself is in flash-base).
    recipes = target(root, "/var/db/fpm/recipes/main")
    if os.path.isdir(recipes):
        shutil.rmtree(recipes)
    shutil.copytree("/var/db/fpm/recipes/main", recipes, symlinks=True)

    # Console keymap: Calamares writes /etc/vconsole.conf (systemd's file);
    # OpenRC reads /etc/conf.d/keymaps.
    keymap = None
    try:
        with open(target(root, "/etc/vconsole.conf")) as f:
            for line in f:
                if line.startswith("KEYMAP="):
                    keymap = line.split("=", 1)[1].strip().strip('"')
    except FileNotFoundError:
        pass
    if keymap:
        path = target(root, "/etc/conf.d/keymaps")
        with open(path) as f:
            text = f.read()
        lines = [f'keymap="{keymap}"' if l.startswith("keymap=") else l
                 for l in text.splitlines()]
        with open(path, "w") as f:
            f.write("\n".join(lines) + "\n")

    # With a desktop the login screen owns tty1; a getty there would fight it
    # for the terminal. Text logins stay on tty2-6.
    getty = target(root, "/etc/runlevels/default/agetty.tty1")
    dm = any(os.path.lexists(target(root, "/etc/runlevels/default/" + s)) for s in ("sddm", "lightdm"))
    if dm and os.path.lexists(getty):
        os.unlink(getty)

    os.makedirs(target(root, "/etc/default"), exist_ok=True)
    with open(target(root, "/etc/default/grub"), "w") as f:
        f.write(GRUB_DEFAULTS)
    return None
