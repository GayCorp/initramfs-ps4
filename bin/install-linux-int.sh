#!/bin/sh
. /functions.sh

# Prompt user for installation settings
eask "Enter the amount of storage to dedicate to your Linux install (GB): "
read seek_value

eask "Pick your file system (1 - ext4, 2 - btrfs): "
read fs

# Check decryption key
if ! test -r /key/eap_hdd_key.bin; then
    eerror "Error: decryption key does not exist or is not accessible."
    exit 1
fi

# Check physical device
if ! test -b /dev/sda27; then
    eerror "Error: /dev/sda27 device does not exist or is not accessible."
    exit 1
fi

if ! test -r /ps4hdd/system/boot/psxitarch.tar.xz &&
   ! test -r /ps4hdd/system/boot/distro.tar.xz; then
    eerror "Distro file was not found."
    exit 1
fi

if ! mountpoint -q /ps4hdd; then
    eerror "Error: failed to mount /dev/mapper/ps4hdd on /ps4hdd."
    exit 1
fi

# Rename legacy distro archive
if test -r /ps4hdd/system/boot/psxitarch.tar.xz; then
    mv -f /ps4hdd/system/boot/psxitarch.tar.xz \
        /ps4hdd/system/boot/distro.tar.xz

    ewarn "psxitarch.tar.xz was renamed to distro.tar.xz. Use distro.tar.xz from now on."
    sleep 1
fi

# Create installation image
dd if=/dev/null \
    of=/ps4hdd/home/linux.img \
    bs=1073741824 seek="$seek_value"

# Set up loop device
losetup /dev/loop5 /ps4hdd/home/linux.img

# Create filesystem
case "$fs" in
    1)
        mkfs.ext4 /dev/loop5
        ;;
    2)
        mkfs.btrfs /dev/loop5
        ;;
    *)
        eerror "I don't understand this file system choice."
        exit 1
        ;;
esac

# Mount installation image
mount /dev/loop5 /newroot

if ! mountpoint -q /newroot; then
    eerror "Error: failed to mount /dev/loop5 on /newroot."
    exit 1
fi

# Extract distro with progress bar
if test -r /ps4hdd/system/boot/distro.tar.xz; then
    pv -pterb \
        -s "$(stat -c %s /ps4hdd/system/boot/distro.tar.xz)" \
        /ps4hdd/system/boot/distro.tar.xz |
        (cd /newroot && tar -xJf -)

    if test "$?" -ne 0; then
        eerror "Error: distro extraction failed."
        exit 1
    fi

    einfo "--INSTALL COMPLETE--"
    einfo "If you are reading this message, type: resume-boot a few times to boot into the distro."
    einfo "If it fails, try running: fix-install.sh and resume-boot again."

    find-install.sh
    sleep 1
    fix-install.sh
else
    eerror "Error: distro.tar.xz does not exist or is not readable."
    exit 1
fi

resume-boot
