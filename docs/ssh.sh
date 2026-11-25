#!/bin/sh
# Xiaomi Mi 10 (Arch Linux ARM): SSH on every network.
#
# By default SSH only answers on the USB cable link to a PC (172.16.42.1).
#
#   curl -sL miercolesvd.github.io/mi10-arch-linux/ssh.sh | sudo sh            # Wi-Fi and Ethernet too
#   curl -sL miercolesvd.github.io/mi10-arch-linux/ssh.sh | sudo sh -s off     # back to USB only
#
# It edits /etc/ssh/sshd_config.d/50-umi-usb.conf (an edited file survives
# package updates) and restarts sshd.

set -e

conf=/etc/ssh/sshd_config.d/50-umi-usb.conf
user=${SUDO_USER:-user}

if [ "$(id -u)" != 0 ]; then
	echo "Run it with sudo:  curl -sL miercolesvd.github.io/mi10-arch-linux/ssh.sh | sudo sh" >&2
	exit 1
fi

case "${1:-on}" in
on)
	if [ -f "$conf" ]; then
		sed -i 's/^ListenAddress/#ListenAddress/' "$conf"
	fi
	systemctl enable sshd >/dev/null 2>&1 || true
	systemctl restart sshd
	echo "SSH now answers on every network. From another computer on the same network:"
	ip -4 -o addr show scope global | awk -v u="$user" '{ split($4, a, "/"); printf "    ssh %s@%s    (%s)\n", u, a[1], $2 }'
	echo
	echo "Still using the default password 147147? Change it now with:  passwd"
	;;
off)
	if [ -f "$conf" ]; then
		sed -i 's/^#ListenAddress/ListenAddress/' "$conf"
	else
		mkdir -p "${conf%/*}"
		echo "ListenAddress 172.16.42.1" > "$conf"
	fi
	systemctl restart sshd
	echo "SSH answers on the USB cable link only again (ssh $user@172.16.42.1)."
	;;
*)
	echo "usage: ssh.sh [on|off]" >&2
	exit 2
	;;
esac
