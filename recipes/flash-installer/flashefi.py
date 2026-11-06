#!/usr/bin/env python3
# Calamares job, after the bootloader: copy GRUB to the fallback path
# EFI/BOOT/BOOTX64.EFI as well, so the disk still boots when the firmware
# forgets (or never saves) the "flash" boot entry. Only when that path is free:
# another system's fallback loader on a shared EFI partition is left alone.

import os
import shutil

import libcalamares


def pretty_name():
    return "Installing the fallback boot loader"


def run():
    if not os.path.isdir("/sys/firmware/efi"):
        return None
    root = libcalamares.globalstorage.value("rootMountPoint")
    esp = libcalamares.globalstorage.value("efiSystemPartition") or "/boot/efi"
    efi = os.path.join(root, esp.lstrip("/"), "EFI")
    grub = os.path.join(efi, "flash", "grubx64.efi")
    if not os.path.isfile(grub):
        return ("Boot loader missing", "GRUB was not found at " + grub)

    # FAT is case-insensitive, but look for any spelling of an existing loader.
    for d in os.listdir(efi):
        if d.lower() == "boot":
            for f in os.listdir(os.path.join(efi, d)):
                if f.lower() == "bootx64.efi":
                    libcalamares.utils.debug("flashefi: keeping the existing " + f)
                    return None
    os.makedirs(os.path.join(efi, "BOOT"), exist_ok=True)
    shutil.copy2(grub, os.path.join(efi, "BOOT", "BOOTX64.EFI"))
    return None
