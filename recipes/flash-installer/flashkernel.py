#!/usr/bin/env python3
# Calamares job, on the "native kernel" ISO only: compile the kernel for this
# computer's CPU (the linux-native package, -march=native) inside the new
# system, replacing the prebuilt one. It builds on the target disk, not in
# the live system's RAM. The native ISO has a native/ folder with the kernel
# source; the prebuilt ISO doesn't, and skips this job.

import os
import shutil
import subprocess
import time

import libcalamares

MEDIUM = "/run/live/medium/native"
SOURCES = "/var/cache/fpm/sources"
# About this many lines in the build log for a whole kernel build (one per
# compiled file); only used to estimate the progress bar.
EXPECTED_LINES = 26000


def pretty_name():
    return "Compiling the kernel for this computer (30–90 minutes)"


def native_iso():
    return os.path.isdir(MEDIUM)


def remote_sources(recipe):
    """File names of a recipe's downloaded sources ("name::url" or a URL)."""
    names = []
    with open(recipe) as f:
        for line in f:
            if line.startswith("source"):
                for src in line.split("=", 1)[1].split():
                    if "://" in src:
                        names.append(src.split("::")[0] if "::" in src else src.rsplit("/", 1)[1])
    return names


def run():
    if not native_iso():
        return None
    root = libcalamares.globalstorage.value("rootMountPoint")
    if not root:
        return ("No target", "The target partition is not mounted.")

    # The kernel's source tarball comes from the live medium (its recipe was
    # copied by flashcfg); nothing is downloaded.
    dest = os.path.join(root, SOURCES.lstrip("/"))
    os.makedirs(dest, exist_ok=True)
    for f in remote_sources(os.path.join(root, "var/db/fpm/recipes/main/linux-native/recipe")):
        src = os.path.join(MEDIUM, f)
        if not os.path.exists(src):
            return ("Kernel source missing", f"{f} isn't on the live medium.")
        shutil.copy2(src, dest)

    log = os.path.join(root, "var/cache/fpm/logs/linux-native.log")
    try:
        os.remove(log)
    except OSError:
        pass
    # Lowest CPU and disk priority: the build takes every core, but the
    # installer window and the desktop stay responsive.
    nice = ["nice", "-n", "19"] + (["ionice", "-c", "3"] if shutil.which("ionice") else [])
    # The build files for out-of-tree modules (NVIDIA) switch along with it.
    pkgs = ["linux-native"]
    if os.path.isdir(os.path.join(root, "var/lib/fpm/installed/linux-devel")):
        pkgs.append("linux-native-devel")
    proc = subprocess.Popen(nice + ["chroot", root, "fpm", "-y", "--overwrite", "install"] + pkgs,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    while proc.poll() is None:
        time.sleep(5)
        try:
            with open(log, "rb") as f:
                lines = sum(1 for _ in f)
            libcalamares.job.setprogress(min(lines / EXPECTED_LINES, 0.98))
        except OSError:
            pass
    out = proc.stdout.read() if proc.stdout else ""
    libcalamares.utils.debug("fpm install linux-native: " + out)
    if proc.returncode != 0:
        tail = ""
        try:
            with open(log, errors="replace") as f:
                tail = "".join(f.readlines()[-15:])
        except OSError:
            pass
        # The prebuilt kernel is still installed, so the system boots anyway.
        libcalamares.utils.warning("linux-native failed to build; keeping the prebuilt kernel")
        return ("The kernel couldn't be compiled",
                "Flash Linux is installed with the prebuilt kernel instead, so it will "
                "still start. You can try again later with: sudo fpm install linux-native\n\n" + tail)
    libcalamares.job.setprogress(1.0)
    return None
