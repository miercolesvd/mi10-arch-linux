#!/bin/sh
# Xiaomi Mi 10 (Arch Linux ARM): collect logs for a bug report.
#
#   curl -sL miercolesvd.github.io/mi10-arch-linux/diag.sh | sudo sh
#
# Writes mi10-diag.txt to your home folder: modem start-up, battery and
# charger state, kernel messages. Only reads; changes nothing on the phone.

home=$(getent passwd "${SUDO_USER:-$(id -un)}" | cut -d: -f6)
out="${home:-/tmp}/mi10-diag.txt"

section() {
	printf '\n===== %s\n' "$*"
}

{
	section "versions"
	uname -a
	pacman -Q linux-xiaomi-umi umi-device umi-modem msm-firmware-loader qrtr 2>&1

	section "services"
	systemctl status msm-firmware-loader umi-tqftpserv umi-modem umi-modem-data --no-pager 2>&1

	section "service logs"
	journalctl -b -u msm-firmware-loader -u umi-tqftpserv -u umi-modem -u umi-modem-data \
		--no-pager 2>&1 | tail -n 150

	section "firmware path and modem partition"
	cat /sys/module/firmware_class/parameters/path 2>&1
	ls /run/msm-firmware-loader/mnt/ 2>&1
	ls /run/msm-firmware-loader/mnt/modem/image/sdx55m 2>&1 | head -n 40

	section "PCIe devices"
	for d in /sys/bus/pci/devices/*; do
		[ -e "$d" ] || continue
		echo "${d##*/} $(cat "$d/vendor" 2>/dev/null):$(cat "$d/device" 2>/dev/null) driver=$(basename "$(readlink "$d/driver" 2>/dev/null)" 2>/dev/null)"
	done
	ls -d /sys/bus/pci/devices/*/mhi* 2>&1

	section "modules"
	ls /sys/module | grep -E 'mhi|qrtr|rmnet|wwan' 2>&1
	cat /usr/lib/modprobe.d/umi-modem.conf 2>&1

	section "network interfaces"
	ip -br link 2>&1
	ip -br addr 2>&1
	ip route 2>&1

	section "battery and charger"
	for p in /sys/class/power_supply/*; do
		[ -e "$p" ] || continue
		echo "--- ${p##*/}"
		grep -H . "$p"/type "$p"/status "$p"/online "$p"/present "$p"/capacity \
			"$p"/current_now "$p"/voltage_now "$p"/usb_type "$p"/charge_type \
			"$p"/health 2>/dev/null | sed "s|^$p/||"
	done
	upower -d 2>/dev/null | head -n 60

	section "kernel messages: modem, PCIe, charging"
	dmesg 2>&1 | grep -iE 'mhi|sdx|sahara|pcie|pci |qrtr|umi-modem|rmnet|wwan|smb5|pm8150b|fuel|charger|bq2597|typec|tcpm' | tail -n 250

	section "kernel messages: errors and warnings"
	dmesg --level=err,warn 2>&1 | tail -n 120
} > "$out" 2>&1

[ -n "$SUDO_USER" ] && chown "$SUDO_USER": "$out"
echo "Wrote $out"
