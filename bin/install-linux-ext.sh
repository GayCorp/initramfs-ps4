#!/bin/sh
. /functions.sh

src=/temp
boot=''

disk_info() {
	local name="${1#/dev/}"
	local model="$(cat "/sys/block/${name}/device/model" 2>/dev/null)"
	local size="$(cat "/sys/block/${name}/size")"
	echo "${1} \"${model:-Unknown}\" $((size / 2048)) MB"
}

has_boot_files() {
	[ -f "${1}/bzImage" ] && [ -f "${1}/initramfs.cpio.gz" ]
}

has_files() {
	has_boot_files "${1}" && { [ -n "${internal_distro}" ] || ps4_find_distro "${1}" >/dev/null; }
}

pick_disk() {
	local n=1 d
	for d in ${disks}; do
		echo "${n} - $(disk_info "${d}")"
		n=$((n + 1))
	done
	eask "$1"
	read selection
	n=1
	for d in ${disks}; do
		if [ "${n}" = "${selection}" ]; then
			picked="${d}"
			return 0
		fi
		n=$((n + 1))
	done
	eerror "Invalid drive selection."
	exit 1
}

if mountpoint -q /newroot && ! umount /newroot; then
	eerror "/newroot is busy, can not install."
	exit 1
fi
mountpoint -q "${src}" && umount "${src}"
mkdir -p "${src}"

internal=''
part="$(ps4hdd_part)" && internal="${part%27}"

# Open the internal PS4 drive so we can look for install files there.
internal_root=''
if mountpoint -q /ps4hdd; then
	internal_root=/ps4hdd
elif [ -n "${part}" ] && command -v ps4hdd_open >/dev/null 2>&1 && ps4hdd_open 2>/dev/null; then
	internal_root=/ps4hdd
fi
[ -n "${internal_root}" ] && boot="${internal_root}/system/boot"

# Look for a distro tarball on the internal drive. If present, the source
# USB no longer needs to contain it.
internal_distro=''
if [ -n "${boot}" ] && [ -d "${boot}" ]; then
	if internal_distro="$(ps4_find_distro "${boot}" 2>/dev/null)"; then
		einfo "Found $(basename "${internal_distro}") on the internal drive."
	else
		internal_distro=''
	fi
fi

all=''
for d in /dev/sd[a-z]; do
	[ -b "${d}" ] && [ "${d}" != "${internal}" ] && all="${all} ${d}"
done

# If the internal drive has bzImage, initramfs and the distro, we do not
# need a source USB at all - only a target USB.
source=''
srcdir=''
source_is_internal=''
if [ -n "${internal_distro}" ] && [ -n "${boot}" ] && has_boot_files "${boot}"; then
	source=internal
	source_is_internal=1
	srcdir="${boot}"
	einfo "Using install files from the internal PS4 drive."
else
	einfo "Searching for the USB device with the install files..."
	for d in ${all}; do
		if mount -o ro "${d}1" "${src}" 2>/dev/null; then
			if has_files "${src}"; then
				source="${d}"
				srcdir="${src}"
				break
			fi
			umount "${src}"
		fi
	done

	if [ -z "${source}" ]; then
		ewarn "No USB device with bzImage, initramfs.cpio.gz and a distro tarball was found."
		disks="${all}"
		[ -n "${disks}" ] || { eerror "No USB drives found."; exit 1; }
		pick_disk "Pick the installation source drive: "
		source="${picked}"
		if ! mount -o ro "${source}1" "${src}"; then
			eerror "Could not mount ${source}1."
			exit 1
		fi
		if ! has_files "${src}"; then
			umount "${src}"
			eerror "${source}1 does not contain the required files."
			exit 1
		fi
		srcdir="${src}"
	fi
fi

if [ -n "${source_is_internal}" ]; then
	einfo "Install files: internal drive"
else
	einfo "Install files: $(disk_info "${source}")"
fi

# Prefer the distro next to the boot files, fall back to internal.
distro=''
if ! distro="$(ps4_find_distro "${srcdir}" 2>/dev/null)"; then
	distro="${internal_distro}"
fi
if [ -z "${distro}" ]; then
	[ -n "${source_is_internal}" ] || umount "${src}"
	eerror "No distro tarball found."
	exit 1
fi

disks=''
if [ -n "${source_is_internal}" ]; then
	disks="${all}"
else
	for d in ${all}; do
		[ "${d}" != "${source}" ] && disks="${disks} ${d}"
	done
fi
if [ -z "${disks}" ]; then
	[ -n "${source_is_internal}" ] || umount "${src}"
	eerror "No USB drive to install onto. Plug in a USB drive."
	exit 1
fi

einfo "Select the drive to install Linux onto. EVERYTHING ON IT WILL BE ERASED."
pick_disk "Pick the installation drive: "
target="${picked}"

ewarn "All data on $(disk_info "${target}") will be erased."
eask "Type YES to continue: "
read answer
if [ "${answer}" != 'YES' ]; then
	[ -n "${source_is_internal}" ] || umount "${src}"
	eerror "Aborted."
	exit 1
fi

for p in "${target}"[0-9]*; do
	[ -b "${p}" ] && grep -q "^${p} " /proc/mounts && umount "${p}"
done

name="${target#/dev/}"
lbs="$(cat "/sys/block/${name}/queue/logical_block_size")"
total=$(($(cat "/sys/block/${name}/size") * 512 / lbs))
[ "${total}" -gt 4294967295 ] && total=4294967295
fat_first=2048
fat_last=$((fat_first + 52428800 / lbs - 1))
ext_first=$((fat_last + 1))
ext_last=$((total - 1))

einfo "Partitioning ${target}..."
printf 'o\nn\np\n1\n%s\n%s\nn\np\n2\n%s\n%s\nt\n1\nc\nw\n' \
	"${fat_first}" "${fat_last}" "${ext_first}" "${ext_last}" | fdisk -u "${target}" >/dev/null
blockdev --rereadpt "${target}" 2>/dev/null

n=0
while ! [ -b "${target}1" ] || ! [ -b "${target}2" ]; do
	n=$((n + 1))
	if [ "${n}" -gt 10 ]; then
		[ -n "${source_is_internal}" ] || umount "${src}"
		eerror "Partitions on ${target} did not show up."
		exit 1
	fi
	sleep 1
done

einfo "Formatting the boot partition..."
if ! mkfs.vfat "${target}1" >/dev/null || ! mount "${target}1" /newroot; then
	[ -n "${source_is_internal}" ] || umount "${src}"
	eerror "Could not format or mount ${target}1."
	exit 1
fi
cp "${srcdir}/bzImage" "${srcdir}/initramfs.cpio.gz" /newroot/
[ -f "${srcdir}/bootargs.txt" ] && cp "${srcdir}/bootargs.txt" /newroot/
umount /newroot

einfo "Formatting the Linux partition..."
if ! mke2fs-new -q -t ext4 -F -L psxitarch -O ^has_journal "${target}2" || ! mount "${target}2" /newroot; then
	[ -n "${source_is_internal}" ] || umount "${src}"
	eerror "Could not format or mount ${target}2."
	exit 1
fi

einfo "Extracting $(basename "${distro}"), do not remove the USB drives or turn off the PS4..."
if ! ps4_extract "${distro}"; then
	[ -n "${source_is_internal}" ] || umount "${src}"
	eerror "Distro extraction failed."
	exit 1
fi
[ -n "${source_is_internal}" ] || umount "${src}"

if [ -r /key/eap_hdd_key.bin ]; then
	mkdir -p /newroot/etc/cryptmount
	cp /key/eap_hdd_key.bin /newroot/etc/cryptmount/
fi
ps4_prepare_newroot
sync

einfo "--INSTALL COMPLETE--"
einfo "Booting..."
resume-boot
