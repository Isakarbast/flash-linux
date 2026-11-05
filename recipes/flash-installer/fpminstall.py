#!/usr/bin/env python3
# Calamares job: install Flash Linux into the target with fpm, from the
# package repository on the live medium. The package groups come from the
# Desktop, Graphics and Extras pages (packagechooser instances).

import re
import subprocess

import libcalamares

CONFIG = "/etc/fpm/installer.conf"


def pretty_name():
    return "Installing packages"


def chosen(instance):
    value = libcalamares.globalstorage.value("packagechooser_" + instance) or ""
    return [v for v in value.split(",") if v]


def run():
    root = libcalamares.globalstorage.value("rootMountPoint")
    if not root:
        return ("No target", "The target partition is not mounted.")

    packages = ["flash-base"]
    packages += chosen("desktop")
    extras = chosen("extras")
    packages += extras
    if "nvidia" in chosen("driver"):
        packages.append("nvidia")
        if "flash-gaming" in extras:
            packages.append("lib32-nvidia")
    libcalamares.utils.debug("fpminstall: " + " ".join(packages))

    # The target starts without the repository's index; without it fpm would
    # fall back to the recipes and build everything from source.
    fpm = ["fpm", "--root", root, "--config", CONFIG]
    sync = subprocess.run(fpm + ["sync"], stdout=subprocess.PIPE,
                          stderr=subprocess.STDOUT, text=True)
    libcalamares.utils.debug("fpm sync: " + sync.stdout)
    if sync.returncode != 0:
        return ("Package repository unreadable",
                "fpm could not read the packages on the live medium:\n" + sync.stdout)

    # fpm prints one "==> Installing name" line per package; count them for the
    # progress bar against the number it plans ("Packages (N):").
    proc = subprocess.Popen(fpm + ["-y", "install"] + packages, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, text=True, bufsize=1)
    total, done, tail = 0, 0, []
    for line in proc.stdout:
        line = line.rstrip()
        tail = (tail + [line])[-20:]
        libcalamares.utils.debug("fpm: " + line)
        # Everything is on the medium; a build means a package is missing.
        if line.startswith("==> Building "):
            proc.kill()
            proc.wait()
            return ("Package missing from the live medium",
                    "fpm wanted to build a package from source instead of "
                    "installing it:\n" + line)
        m = re.match(r"Packages \((\d+)\):", line)
        if m:
            total = int(m.group(1))
        elif line.startswith("==> Installing ") and total:
            done += 1
            libcalamares.job.setprogress(min(done / total, 0.99))
    if proc.wait() != 0:
        return ("Package installation failed",
                "fpm could not install the system:\n" + "\n".join(tail))
    libcalamares.job.setprogress(1.0)
    return None
