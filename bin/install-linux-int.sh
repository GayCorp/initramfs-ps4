#!/bin/sh
. /functions.sh

boot=/ps4hdd/system/boot
img=/ps4hdd/app/linux.img
mkdir -p /ps4hdd/app
if ! ps4hdd_open; then
	eerror "Could not open the PS4 internal drive."
	exit 1
fi

if [ -f "${boot}/psxitarch.tar.xz" ] && ! [ -f "${boot}/distro.tar.xz" ]; then
	mv -f "${boot}/psxitarch.tar.xz" "${boot}/distro.tar.xz"
	ewarn "psxitarch.tar.xz was renamed to distro.tar.xz. Use distro.tar.xz from now on."
fi

if ! distro="$(ps4_find_distro "${boot}")"; then
	eerror "No distro.tar.xz, distro.tar.gz or distro.tar.bz2 in ${boot}."
	exit 1
fi

if mountpoint -q /newroot && ! umount /newroot; then
	eerror "/newroot is busy, can not install."
	exit 1
fi

if [ -e "${img}" ]; then
	ewarn "${img} already exists. Installing again erases it."
	eask "Type YES to erase it: "
	read answer
	if [ "${answer}" != 'YES' ]; then
		eerror "Aborted."
		exit 1
	fi
	rm -f "${img}"
fi

free_gb="$(df -Pk /ps4hdd | awk 'END { print int($4 / 1048576) }')"
if [ "${free_gb}" -lt 1 ]; then
	eerror "Less than 1 GB free on the internal drive."
	exit 1
fi

eask "Enter the amount of storage to dedicate to your Linux install (1-${free_gb} GB): "
read size
case "${size}" in
	''|*[!0-9]*)
		eerror "'${size}' is not a number."
		exit 1
	;;
esac
if [ "${size}" -lt 1 ] || [ "${size}" -gt "${free_gb}" ]; then
	eerror "Size must be between 1 and ${free_gb} GB."
	exit 1
fi

eask "Pick your file system (1 - ext4, 2 - btrfs): "
read fs
case "${fs}" in
	1|2) ;;
	*)
		eerror "I don't understand this file system choice."
		exit 1
	;;
esac

if ! dd if=/dev/null of="${img}" bs=1048576 count=0 seek="$((size * 1024))" 2>/dev/null; then
	eerror "Could not create ${img}."
	exit 1
fi

case "${fs}" in
	1) mkfs.ext4 -q -F -O ^orphan_file,^metadata_csum_seed "${img}" ;;
	2) mkfs.btrfs -q -f "${img}" ;;
esac
if [ "$?" -ne 0 ]; then
	eerror "Could not create the file system."
	rm -f "${img}"
	exit 1
fi

if ! mount "${img}" /newroot; then
	eerror "Could not mount ${img} on /newroot."
	exit 1
fi

einfo "Extracting $(basename "${distro}"), do not turn off the PS4..."
if ! ps4_extract "${distro}"; then
	eerror "Distro extraction failed."
	exit 1
fi
ps4_prepare_newroot
sync

einfo "--INSTALL COMPLETE--"
einfo "Booting..."
resume-boot
