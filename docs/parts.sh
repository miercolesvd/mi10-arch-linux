#!/bin/sh
# Xiaomi Mi 10 (Arch Linux ARM): look at, or back up, the phone's own partitions.
#
#   curl -sL miercolesvd.github.io/mi10-arch-linux/parts.sh | sudo sh              # mount them read-only under /mnt/p
#   curl -sL miercolesvd.github.io/mi10-arch-linux/parts.sh | sudo sh -s umount    # unmount them again
#   curl -sL miercolesvd.github.io/mi10-arch-linux/parts.sh | sudo sh -s backup    # copy them to ~/partbackup
#
# Only partitions on the phone's flash are touched, never USB drives. The
# Arch Linux partition (userdata) is left alone. Mounts are read-only, and
# ext4 journals are not replayed, so nothing on the partitions changes.

set -e

user=${SUDO_USER:-user}
home=$(getent passwd "$user" | cut -d: -f6)
mnt=/mnt/p

if [ "$(id -u)" != 0 ]; then
	echo "Run it with sudo:  curl -sL miercolesvd.github.io/mi10-arch-linux/parts.sh | sudo sh" >&2
	exit 1
fi

# Print "name device" for every partition on the phone's flash (UFS)
phone_parts() {
	for link in /dev/disk/by-partlabel/*; do
		dev=$(readlink -f "$link")
		case "$(readlink -f "/sys/class/block/${dev##*/}")" in
		*ufshc*) echo "${link##*/} $dev" ;;
		esac
	done
}

case "${1:-mount}" in
mount)
	mkdir -p "$mnt"
	phone_parts | while read -r name dev; do
		[ "$name" = userdata ] && continue
		type=$(blkid -o value -s TYPE "$dev" 2>/dev/null || true)
		case "$type" in
		ext2|ext3|ext4) opts=ro,noload ;;
		f2fs) opts=ro,norecovery ;;
		vfat|erofs|squashfs) opts=ro ;;
		*) continue ;;
		esac
		# A click in the file manager mounts these read-write under
		# /run/media; swap those for read-only mounts
		for where in $(findmnt -rn -S "$dev" -o TARGET); do
			case "$where" in
			/run/media/*) umount "$where" && echo "unmounted $where (it was read-write)" ;;
			esac
		done
		if where=$(findmnt -rn -S "$dev" -o TARGET | head -n1) && [ -n "$where" ]; then
			echo "$name ($type) is already mounted at $where"
			continue
		fi
		mkdir -p "$mnt/$name"
		mount -t "$type" -o "$opts" "$dev" "$mnt/$name" && echo "$name ($type) -> $mnt/$name"
	done
	echo
	echo "Read-only. Browse them in Dolphin at $mnt, or: ls $mnt"
	echo "Partitions without a filesystem (raw data) are not mounted; 'backup' copies them."
	;;
umount|unmount|off)
	for d in "$mnt"/*; do
		[ -d "$d" ] || continue
		mountpoint -q "$d" && umount "$d"
		rmdir "$d" 2>/dev/null || true
	done
	rmdir "$mnt" 2>/dev/null || true
	echo "Unmounted."
	;;
backup)
	dest="$home/partbackup"
	need=0
	list=$(phone_parts | grep -v -e '^userdata ' -e '^super ')
	for dev in $(echo "$list" | cut -d' ' -f2); do
		need=$((need + $(blockdev --getsize64 "$dev")))
	done
	mkdir -p "$dest"
	free=$(df -B1 --output=avail "$dest" | tail -n1)
	if [ "$need" -gt "$free" ]; then
		echo "Not enough space: need $((need >> 20)) MiB, $((free >> 20)) MiB free." >&2
		exit 1
	fi
	echo "Copying $(echo "$list" | wc -l) partitions ($((need >> 20)) MiB) to $dest ..."
	echo "$list" | while read -r name dev; do
		dd if="$dev" of="$dest/$name.img" bs=4M status=none || echo "could not read $name" >&2
	done
	(cd "$dest" && sha256sum ./*.img > SHA256SUMS)
	chown -R "$user:" "$dest"
	echo "Done: $(du -sh "$dest" | cut -f1) in $dest (super and userdata are not included)."
	echo "Now copy it to another computer, for example:"
	echo "    scp -r $user@<phone address>:partbackup ."
	;;
*)
	echo "usage: parts.sh [mount|umount|backup]" >&2
	exit 2
	;;
esac
