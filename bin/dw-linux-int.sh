#!/bin/sh

. /functions.sh
SetupNetwork
url='http://gatto.fae5.de/ps4linux/artix.tar.xz'
distro=/ps4hdd/system/distro.tar.xz

if ! ps4hdd_open; then
	eerror "Could not open the PS4 internal drive."
	exit 1
fi

if ! SetupNetwork; then
	exit 1
fi

mkdir -p /ps4hdd/system || {
	eerror "Could not create /ps4hdd/system."
	exit 1
}

einfo "Downloading Artix Linux..."
set -o pipefail
/bin/busybox wget -O - "${url}" | pv -pterb > "${distro}"
download_status=$?
set +o pipefail
if [ "${download_status}" -ne 0 ]; then
	rm -f "${distro}"
	eerror "Could not download the Linux distribution."
	exit 1
fi

install-linux-int.sh