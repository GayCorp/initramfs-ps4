#!/bin/sh
# better-initramfs project
# https://bitbucket.org/piotrkarbowski/better-initramfs
# Copyright (c) 2010-2013, Piotr Karbowski <piotr.karbowski@gmail.com>
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#    * Redistributions of source code must retain the above copyright notice,
#      this list of conditions and the following disclaimer.
#    * Redistributions in binary form must reproduce the above copyright notice,
#      this list of conditions and the following disclaimer in the documentation
#      and/or other materials provided with the distribution.
#    * Neither the name of the Piotr Karbowski nor the names of its contributors
#      may be used to endorse or promote products derived from this software
#      without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
# THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE

initramfs_quiet=false

quiet_mode() {
	[ "${initramfs_quiet:-false}" = 'true' ]
}

einfo() {
	quiet_mode && return 0
	echo -ne "\033[1;30m>\033[0;36m>\033[1;36m> \033[0m${*}\n" ;
}
ewarn() {
	quiet_mode && return 0
	echo -ne "\033[1;30m>\033[0;33m>\033[1;33m> \033[0m${*}\n" >&2;
}
eerror() { echo -ne "\033[1;30m>\033[0;31m>\033[1;31m> ${*}\033[0m\n" >&2 ;}
eask() {
	quiet_mode && return 0
	echo -ne "\033[1;30m>\033[0;35m>\033[1;35m> \033[0m${*}";
}
die() { eerror "$*"; rescueshell; }


InitializeBusybox() {
	einfo "Create all the symlinks to /bin/busybox."
	run /bin/busybox --install -s
}

rescueshell() {
	initramfs_quiet=false
	if [ "$rescueshell" != 'true' ]; then
		# If we did not forced rescueshell by kernel opt, print additional message.
		ps4_change_led orange
		ewarn "Dropping to rescueshell because of above error."
	fi
	
	ewarn "Rescue Shell (busybox's /bin/sh)"
	ewarn "To reboot, press 'control-alt-delete'."
	ewarn "If you wish resume booting process, run 'resume-boot'."
	if [ "$console" ] && [ -c "/dev/${console}" ]; then
		setsid sh -c "exec sh --login </dev/"${console}" >/dev/${console} 2>&1"
	elif [ -c '/dev/tty1' ]; then
		setsid sh -c 'exec sh --login </dev/tty1 >/dev/tty1 2>&1'
	else
		sh --login
	fi
	echo
	:> /rescueshell.pid
}

was_shell() {
	[ -f '/rescueshell.pid' ]
	return $?
}

run() {
	if "$@"; then
		echo "Executed: '$@'" >> /init.log
	else
		eerror "'$@' failed."
		echo "Failed: '$@'" >> /init.log
		echo "$@" >> /.ash_history
		rescueshell
	fi
}

get_opt() {
	echo "${*#*=}"
}

run_hooks() {
	# Support for optional code injection via hooks placed into
	# multiple initramfs images.
	if [ -d "/hooks/$1" ]; then
		for i in /hooks/$1/*; do
			[ "$i" = "/hooks/$1/*" ] && break
			chmod +x "$i" 2>/dev/null
			einfo "Running '$i' hook ..."
			. "$i"
		done
	fi
}

resolve_device() {
	# This function will check if variable at $1 contain LABEL or UUID and then, if LABEL/UUID is vaild.
	device="$(eval echo \$$1)"
	case "${device}" in
		LABEL\=*|UUID\=*)
			eval $1="$(findfs $device)"
			if [ -z "$(eval echo \$$1)" ]; then
				eerror "Wrong UUID or LABEL."
				rescueshell
			fi
		;;
	esac
}

process_commandline_options() {
	for i in $(cat /proc/cmdline); do
		case "${i}" in
			initramfsdebug)
				set -x
			;;
			root\=*)
				root=$(get_opt $i)
			;;
			init\=*)
				init=$(get_opt $i)
			;;
			enc_root\=*)
				enc_root=$(get_opt $i)
			;;
			luks)
				luks=true
			;;
			lvm)
				lvm=true
			;;
			softraid)
				softraid=true
			;;
			rescueshell)
				rescueshell=true
			;;
			swsusp)
				swsusp=true
			;;
			uswsusp)
				uswsusp=true
			;;
			tuxonice)
				tuxonice=true
			;;
			resume\=*)
				resume=$(get_opt $i)
			;;
			rootfstype\=*)
				rootfstype=$(get_opt $i)
			;;

			rootflags\=*)
				rootfsmountparams="-o $(get_opt $i)"
			;;

			ro|rw)
				root_rw_ro=$i
			;;
			rootdelay\=*)
				rootdelay=$(get_opt $i)
			;;
			console\=*)
				console=$(get_opt $i)
				console="${console%,*}"
			;;
			mdev)
				mdev=true
			;;
			luks_no_discards)
				luks_no_discards=true
			;;
			bcache)
				bcache=true
			;;
		esac
	done
}

has_cmdline() {
	local option="$1"
	[ -n "${option}" ] || return 1

	for i in $(cat /proc/cmdline); do
		case "${i}" in
			initramfs=*)
				local value
				value=$(get_opt "$i")
				local old_ifs="${IFS}"
				IFS=','
				for item in ${value}; do
					if [ "${item}" = "${option}" ]; then
						IFS="${old_ifs}"
						return 0
					fi
				done
				IFS="${old_ifs}"
			;;
		esac
	done
	return 1
}

use() {
	name="$(eval echo \$$1)"
	# Check if $name isn't empty and if $name isn't set to false or zero.
	if [ -n "${name}" ] && [ "${name}" != 'false' ] && [ "${name}" != '0' ]; then
		if [ -n "$2" ]; then
			$2
		else
			return 0
		fi
	else
		return 1
	fi
}

musthave() {
	while [ -n "$1" ]; do
		# We can handle it by use() function, yay!
		if ! use "$1"; then
			eerror "The \"$1\" variable is empty, set to false or zero but shoudn't be."
			local missing_variable='true'
		fi
		shift
	done

	if [ "${missing_variable}" = 'true' ]; then
		rescueshell
	fi
}

dodir() {
	for dir in "$@"; do
		run mkdir -m 700 -p "${dir}"
	done
}

loadkeymap() {
	if [ -f /keymap ]; then
		loadkmap < /keymap
	fi
}

get_majorminor() {
	local device="$1"
	musthave device

	local major_hex="$(stat -L -c '%t' "${device}")"
	local minor_hex="$(stat -L -c '%T' "${device}")"

	musthave major_hex minor_hex

	if [ -n "${major_hex}" ] && [ -n "${minor_hex}" ]; then
		printf '%u:%u\n' "0x${major_hex}" "0x${minor_hex}"
	fi
}

InitializeLUKS() {
	if [ ! -f /bin/cryptsetup ]; then
		eerror "There is no cryptsetup binary into initramfs image."
		rescueshell
	fi

	musthave enc_root

	local enc_num='1'
	local dev_name="enc_root"
	# We will use : to separate devices but we need normal IFS inside the for loop anyway.
	local IFS=":"
	for enc_dev in ${enc_root}; do
		IFS="${default_ifs}"
		if ! [ "${enc_num}" = '1' ]; then
			dev_name="enc_root${enc_num}"
		fi

		resolve_device enc_dev

		einfo "Opening encrypted partition '${enc_dev##*/}' and mapping to '/dev/mapper/${dev_name}'."

		# Hack for cryptsetup which trying to run /sbin/udevadm.
		run echo -e "#!/bin/sh\nexit 0" > /sbin/udevadm
		run chmod 755 /sbin/udevadm

		local cryptsetup_args=""
		if ! use luks_no_discards; then
			cryptsetup_args="${cryptsetup_args} --allow-discards"
		fi

		run cryptsetup luksOpen --tries 25 ${cryptsetup_args} "${enc_dev}" "${dev_name}"
		enc_num="$((enc_num+1))"
	done
}

InitializeLVM() {
	einfo "Scaning all disks for volume groups."
	# We have to ensure that cache does not exist so vgchange will run 'vgscan' itself.
	if [ -d '/etc/lvm/cache' ]; then run rm -rf '/etc/lvm/cache'; fi
	run lvm vgchange -a y
}

InitializeSoftwareRaid() {
	einfo "Scaning for software raid arrays."
	if ! [ -f '/etc/mdadm.conf' ]; then
		run mdadm --examine --scan > /etc/mdadm.conf
	fi
	run mdadm --assemble --scan

	# The software raid arrays may have partitions on them.
	rereadpt
}

rereadpt() {
	# Check for partition table on all block devices.
	for i in /dev/*; do
		if [ -b "${i}" ]; then
			blockdev --rereadpt "${i}" >/dev/null 2>&1
		fi
	done
}

SwsuspResume() {
	musthave resume
	resolve_device resume
	if [ -f '/sys/power/resume' ]; then
		local resume_majorminor="$(get_majorminor "${resume}")"
		musthave resume_majorminor
		echo "${resume_majorminor}" > /sys/power/resume
	else
		ewarn "Apparently this kernel does not support suspend."
	fi
}

UswsuspResume() {
	musthave resume
	resolve_device resume
	if [ -f '/sys/power/resume' ]; then
		run resume --resume_device "${resume}"
	else
		ewarn "Apparently this kernel does not support suspend."
	fi
}

TuxOnIceResume() {
	musthave resume
	if [ -f '/sys/power/tuxonice/do_resume' ]; then
		einfo "Sending do_resume signal to TuxOnIce."
		run echo 1 > /sys/power/tuxonice/do_resume
	else
		ewarn "Apparently this kernel does not support TuxOnIce."
	fi
}

register_bcache_devices() {
	# Push all the block devices to register_quiet
	# If its bcache, it will bring it up, if not, it will simply ignore it.
	if ! [ -e /sys/fs/bcache/register_quiet ]; then
		ewarn "There's no bcache interface. Missing kernel driver?"
		return 0
	fi

	for i in $(awk '$4 !~ /^(name$|$)/ { print $4 }' /proc/partitions); do
		if [ -e "/dev/${i}" ]; then
			echo "/dev/${i}" >/sys/fs/bcache/register_quiet
		else
			echo "Looks like there's no '/dev/${i}', but should be."
		fi
	done
}

cleanup() {
	was_shell && rm /rescueshell.pid
}

boot_newroot() {
	init="${init:-/sbin/init}"
	einfo "Switching root to /newroot and executing ${init}."
	if ! [ -e "/newroot/${init}" ]; then die "There is no executable '/newroot/${init}'."; fi
	if ! [ -x "/newroot/${init}" ]; then die "This is not bootable, you probably extracted this wrong."; fi
	exec env -i \
		TERM="${TERM:-linux}" \
		PATH="${PATH:-/bin:/sbin:/usr/bin:/usr/sbin}" \
			switch_root /newroot "${init}"
}
emount() {
	# All mounts into one place is good idea.
	while [ "$#" -gt 0 ]; do
		case $1 in
			'/newroot')
				if mountpoint -q '/newroot'; then
					einfo "/newroot already mounted, skipping..."
				else
					einfo "Mounting /newroot..."
					musthave root
					if [ -n "${rootfstype}" ]; then
						local mountparams="${rootfsmountparams} -t ${rootfstype}"
					fi
					resolve_device root
					run mount -o ${root_rw_ro:-ro} ${mountparams} "${root}" '/newroot'
				fi
			;;

			'/newroot/usr')
				if [ -f '/newroot/etc/fstab' ]; then
						while read device mountpoint fstype fsflags _; do
						if [ "${mountpoint}" = '/usr' ]; then
							if [ -d '/newroot/usr' ]; then
								einfo "Mounting /newroot/usr..."
								run mount -o "${fsflags},${root_rw_ro:-ro}" -t "${fstype}" "${device}" '/newroot/usr'
							else
								die "/usr in fstab present but no mountpoint /newroot/usr found."
							fi
							break
						fi
					done < '/newroot/etc/fstab'
				else
					ewarn "No /newroot/etc/fstab present."
					ewarn "Early mouting of /usr will not be done."
				fi
			;;

			'/dev')
				local devmountopts='nosuid,relatime,size=10240k,mode=755'

				if grep -q 'devtmpfs' '/proc/filesystems' && ! use mdev; then
					einfo "Mounting /dev (devtmpfs)..."
					run mount -t devtmpfs -o ${devmountopts} devtmpfs /dev
				else
					einfo "Mounting /dev (mdev over tmpfs)..."
					run mount -t tmpfs -o ${devmountopts} dev /dev
					run touch /etc/mdev.conf
					run echo /sbin/mdev > /proc/sys/kernel/hotplug
					run mdev -s
					# Looks like mdev create /dev/pktcdvd as a file when both udev and devtmpfs do it as a dir.
					# We will do it 'better' to avoid non-fatal-error while starting udev after switching to /newroot.
					# TODO: Can mdev.conf handle it?
					if [ -c '/dev/pktcdvd' ]; then
						run rm '/dev/pktcdvd'
						run mkdir '/dev/pktcdvd'
						run mknod '/dev/pktcdvd/control' c 10 61
					fi
				fi
			;;

			'/proc')
				einfo "Mounting /proc..."
				run mount -t proc proc /proc
			;;

			'/sys')
				einfo "Mounting /sys..."
				run mount -t sysfs sysfs /sys
			;;

			*)
				eerror "emount() does not understand \"$1\""
			;;
		esac
		shift
	done
}

eumount() {
	while [ "$#" -gt 0 ]; do
		case "$1" in
			*)
				einfo "Unmounting ${1}..."
				run umount "$1"
			;;
		esac
		shift
	done
}

moveDev() {
	einfo "Moving /dev to /newroot/dev..."
	if mountpoint -q /dev/pts; then umount -l /dev/pts; fi
	if use mdev; then run echo '' > /proc/sys/kernel/hotplug; fi
	run mount --move /dev /newroot/dev
}

rootdelay() {
	if [ "${rootdelay}" -gt 0 2>/dev/null ]; then
		einfo "Waiting ${rootdelay}s (rootdelay)"
		run sleep ${rootdelay}
	else
		ewarn "\$rootdelay variable must be numeric and greater than zero. Skipping rootdelay."
	fi
}

ps4hdd_part() {
	for p in /dev/sd?27; do
		if [ -b "${p}" ]; then
			echo "${p}"
			return 0
		fi
	done
	return 1
}

ps4_change_led() {
	local led_base='/sys/class/leds'
	local color="${1:-}"
	local led_path led_color target

	if [ -z "${color}" ]; then
		return 2
	fi

	target=''
	for led_path in "${led_base}"/ps4:*:status/brightness; do
		[ -e "${led_path}" ] || continue
		led_color=${led_path##*/ps4:}
		led_color=${led_color%:status/brightness}
		if [ "${led_color}" = "${color}" ]; then
			target="${led_path}"
			break
		fi
	done
	if [ -z "${target}" ]; then
		return 1
	fi

	for led_path in "${led_base}"/ps4:*:status/brightness; do
		[ -w "${led_path}" ] || continue
		printf '0\n' > "${led_path}" || return 1
	done
	sleep 1
	printf '255\n' > "${target}"
}

ps4hdd_open() {
	mountpoint -q /ps4hdd && return 0
	if ! [ -b /dev/mapper/ps4hdd ]; then
		if ! [ -r /key/eap_hdd_key.bin ]; then
			ewarn "No /key/eap_hdd_key.bin, the internal drive can not be opened."
			return 1
		fi
		local part
		if ! part="$(ps4hdd_part)"; then
			ewarn "No PS4 internal drive found (no /dev/sd?27)."
			return 1
		fi
		if ps4_is_southbridge "aeolia"; then
			cryptsetup -d /key/eap_hdd_key.bin --cipher aes-xts-plain64 -s 256 --offset 0 create ps4hdd "${part}" || return 1
		else
			cryptsetup -d /key/eap_hdd_key.bin --cipher aes-xts-plain64 -s 256 --offset 0 --skip 111669149696 create ps4hdd "${part}" || return 1
		fi
	fi
	mkdir -p /ps4hdd
	if ! mount -t ufs -o ufstype=ufs2 /dev/mapper/ps4hdd /ps4hdd; then
		eerror "Could not mount /dev/mapper/ps4hdd on /ps4hdd."
		return 1
	fi
}
ps4_southbridge() {
    local sb
    sb=$(dmesg | grep -m1 southbridge | cut -d: -f5 | cut -d"[" -f1 | xargs)

    # Older kernels don't print the southbridge line. On those, the only
    # systems we care about are Baikal, and the kernel release string says so.
    if [ -z "$sb" ]; then
        case "$(uname -r)" in
            *[Bb]aikal*) sb="Baikal A0" ;;
        esac
    fi

    [ -n "$sb" ] || return 1
    printf '%s\n' "$sb"
}
ps4_is_southbridge() {
    local target="${1:-}" current
    [ -n "$target" ] || return 1
    current="$(ps4_southbridge)" || return 1

    target="$(printf '%s' "$target"  | tr 'A-Z' 'a-z')"
    current="$(printf '%s' "$current" | tr 'A-Z' 'a-z')"

    case "$current" in
        "$target" | "$target "*) return 0 ;;
    esac
    return 1
}
ps4_southbridge_code() {
    case "${1:-$(ps4_southbridge)}" in
        "Aeolia A0")  echo 0x10100 ;;
        "Aeolia A1")  echo 0x10200 ;;
        "Aeolia A2")  echo 0x10300 ;;
        "Belize A0")  echo 0x20100 ;;
        "Belize B0")  echo 0x20200 ;;
        "Baikal A0")  echo 0x30100 ;;
        "Baikal B0")  echo 0x30200 ;;
        "Baikal B1")  echo 0x30201 ;;
        "Belize2 A0") echo 0x40100 ;;
        *)            return 1 ;;
    esac
}

ps4_southbridge_name() {
    case "${1:-$(ps4_southbridge_code)}" in
        0x10100) echo "Aeolia A0"  ;;
        0x10200) echo "Aeolia A1"  ;;
        0x10300) echo "Aeolia A2"  ;;
        0x20100) echo "Belize A0"  ;;
        0x20200) echo "Belize B0"  ;;
        0x30100) echo "Baikal A0"  ;;
        0x30200) echo "Baikal B0"  ;;
        0x30201) echo "Baikal B1"  ;;
        0x40100) echo "Belize2 A0" ;;
        *)       return 1 ;;
    esac
}
ps4_wait_disks() {
	local n=0
	while [ "${n}" -lt "${1:-8}" ]; do
		findfs LABEL=psxitarch >/dev/null 2>&1 && return 0
		sleep 1
		n=$((n + 1))
	done
}

ps4_fsck() {
	case "$(blkid "$1" 2>/dev/null)" in
		*'TYPE="ext'*)
			einfo "Checking $1 ..."
			e2fsck -p "$1"
			if [ "$?" -ge 4 ]; then
				ewarn "e2fsck found errors it could not fix on $1."
				ewarn "Run 'e2fsck -f $1' by hand if the boot fails."
			fi
		;;
	esac
}

ps4_find_install() {
	if mountpoint -q /newroot && ! umount /newroot; then
		eerror "/newroot is busy, can not search again."
		return 1
	fi
	local dev
	if dev="$(findfs LABEL=psxitarch 2>/dev/null)"; then
		ps4_fsck "${dev}"
		if mount "${dev}" /newroot; then
			einfo "Mounted external installation (${dev})."
			return 0
		fi
	fi
	if ps4_is_southbridge "baikal"; then # since we're on baikal, don't check internal as its broken
		ewarn "External installation not found."
		return 1
	fi
	ewarn "External installation not found, checking internal drive..."
	if ps4hdd_open && [ -f /ps4hdd/home/linux.img ]; then
		ps4_fsck /ps4hdd/home/linux.img
		if mount /ps4hdd/home/linux.img /newroot; then
			einfo "Mounted internal installation."
			return 0
		fi
	fi
	ewarn "No installation found on internal drive either."
	return 1
}
ps4_prepare_newroot() {
	local d
	for d in dev media mnt proc run sys tmp var/cache var/log var/tmp; do
		mkdir -p "/newroot/${d}"
	done
}

ps4_find_distro() {
	local f
	for f in distro.tar.xz distro.tar.gz distro.tar.bz2 distro.tar psxitarch.tar.xz; do
		if [ -f "$1/${f}" ]; then
			echo "$1/${f}"
			return 0
		fi
	done
	if [ -f "$1/distro.tar.zst" ]; then
		eerror "distro.tar.zst is not supported, recompress it as distro.tar.xz."
	fi
	return 1
}
ps4_current_setup() {
    if [ -f /ps4hdd/system/boot/initramfs.cpio.gz ]; then
        echo "/ps4hdd/system/boot"
        return 0
    fi

    if [ -f /temp/initramfs.cpio.gz ]; then
        echo "/temp"
        return 0
    fi

    return 1
}
ps4_extract() {
	local z=''
	case "$1" in
		*.xz) z='-J' ;;
		*.gz) z='-z' ;;
		*.bz2) z='-j' ;;
	esac
	set -o pipefail
	pv -pterb -s "$(stat -c %s "$1")" "$1" | tar -x ${z} -f - -C /newroot --numeric-owner
	local rc=$?
	set +o pipefail
	return "${rc}"
}

# vim: noexpandtab
