#!/bin/bash
# Build Arch Linux ARM with KDE Plasma for the Xiaomi Mi 10 (umi).
#
# Run as root on an arm64 Linux machine; CI uses GitHub's ubuntu-24.04-arm.
# Needs: arch-chroot (arch-install-scripts), bsdtar (libarchive-tools), curl,
# gpgv, e2fsprogs, rsync, img2simg (android-sdk-libsparse-utils).
#
#   build/build-image.sh OUTDIR
#
# Produces in OUTDIR:
#   boot.img        kernel + initramfs + device tree  -> "boot" partition
#   mi10-arch.img   root filesystem (sparse ext4)     -> "userdata" partition
#   repo/           the Mi 10 packages as a pacman repository ("mi10"), which
#                   installed systems update from
#   packages.txt    installed package versions
#   SHA256SUMS
#
# Environment:
#   PASSWORD        password of the "user" account (default 147147)
#   KERNEL_PKG_DIR  keeps the built kernel package between runs: used if it
#                   holds one for the current version, filled otherwise
#   WORK            scratch directory (default /var/tmp/mi10-build)
#   REPO_SERVER     where installed systems download the mi10 repository
#                   (default: this project's "packages" GitHub release)

set -euo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
OUT=$(realpath -m "${1:?usage: build-image.sh OUTDIR}")
WORK=${WORK:-/var/tmp/mi10-build}
ROOT=$WORK/rootfs
PASSWORD=${PASSWORD:-147147}
KERNEL_PKG_DIR=${KERNEL_PKG_DIR:-}
ALARM_TARBALL=ArchLinuxARM-aarch64-latest.tar.gz
# Plain HTTP: the HTTPS mirrors have mismatched certificates. The download
# is checked against the Arch Linux ARM signing key below either way.
ALARM_URL=http://os.archlinuxarm.org/os/$ALARM_TARBALL
USERNAME=user
REPO_SERVER=${REPO_SERVER:-https://github.com/miercolesvd/mi10-arch-linux/releases/download/packages}

step() { echo; echo "=== $(date -u +%H:%M:%S) $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }
inroot() { arch-chroot "$ROOT" "$@"; }

# Arch Linux ARM's mirror redirector sometimes sends a download to a mirror
# that does not have the package yet (404). Refresh the databases, which
# usually lands on another mirror, and try again.
pac() {
	local i
	for i in 1 2 3; do
		inroot pacman "$@" && return 0
		echo "pacman failed (attempt $i of 3); refreshing the databases and retrying in 20 s"
		sleep 20
		inroot pacman -Syy --noconfirm || true
	done
	die "pacman $* failed 3 times"
}

[ "$(id -u)" = 0 ] || die "run as root"
[ "$(uname -m)" = aarch64 ] || die "run on an arm64 machine (this is $(uname -m))"
for tool in arch-chroot bsdtar curl gpgv mkfs.ext4 rsync img2simg; do
	command -v "$tool" >/dev/null || die "missing tool: $tool"
done

cleanup() {
	mountpoint -q "$WORK/mnt" && umount "$WORK/mnt"
	mountpoint -q "$ROOT" && umount -R "$ROOT"
	true
}
trap cleanup EXIT

mkdir -p "$WORK/dl" "$OUT"

step "Downloading Arch Linux ARM ($ALARM_URL)"
curl -fL --retry 3 -o "$WORK/dl/$ALARM_TARBALL" "$ALARM_URL"
curl -fL --retry 3 -o "$WORK/dl/$ALARM_TARBALL.sig" "$ALARM_URL.sig"
gpg --dearmor < "$REPO/build/archlinuxarm-builder.asc" > "$WORK/alarm.gpg"
gpgv --keyring "$WORK/alarm.gpg" "$WORK/dl/$ALARM_TARBALL.sig" "$WORK/dl/$ALARM_TARBALL" \
	|| die "signature check of $ALARM_TARBALL failed"
echo "signature OK (Arch Linux ARM Build System)"

step "Unpacking the base system"
rm -rf "$ROOT"
mkdir -p "$ROOT"
bsdtar -xpf "$WORK/dl/$ALARM_TARBALL" -C "$ROOT"
# pacman needs the root to be a mount point
mount --bind "$ROOT" "$ROOT"

step "Updating the base system"
# Build-time only, undone at the end: parallel downloads, and no download
# sandbox (it can fail inside a chroot)
cp "$ROOT/etc/pacman.conf" "$WORK/pacman.conf.orig"
sed -i -e 's/^#\?ParallelDownloads.*/ParallelDownloads = 8/' \
	-e '/^\[options\]/a DisableSandbox' "$ROOT/etc/pacman.conf"
inroot pacman-key --init
inroot pacman-key --populate archlinuxarm
pac -Syu --noconfirm

step "Removing the generic Arch Linux ARM kernel"
inroot pacman -Rns --noconfirm linux-aarch64 || true
rm -rf "$ROOT"/boot/{Image,Image.gz,initramfs-linux*.img,dtbs}
rm -f "$ROOT"/etc/mkinitcpio.d/linux-aarch64.preset

step "Checking that all packages exist"
mapfile -t PACKAGES < <(sed -e 's/#.*//' -e '/^\s*$/d' "$REPO/build/packages.txt")
missing=$(inroot sh -c 'for p; do pacman -Si "$p" >/dev/null 2>&1 || echo "$p"; done' sh "${PACKAGES[@]}")
[ -z "$missing" ] || die "not in the Arch Linux ARM repositories: ${missing//$'\n'/ }"
echo "${#PACKAGES[@]} packages found"

step "Installing build tools"
pac -S --needed --noconfirm base-devel bc clang cpio libelf lld llvm meson pahole python
inroot useradd -m builder 2>/dev/null || true
rm -rf "$ROOT/build"
mkdir -p "$ROOT/build/out"
cp -r "$REPO/pkgbuilds/." "$ROOT/build/"
inroot chown -R builder:builder /build
mkdir -p "$ROOT/etc/makepkg.conf.d"
echo "MAKEFLAGS=\"-j$(nproc)\"" > "$ROOT/etc/makepkg.conf.d/zz-mi10-build.conf"

build_pkg() {
	step "Building $1"
	inroot su builder -c "cd /build/$1 && PKGDEST=/build/out makepkg --nodeps --noconfirm --cleanbuild"
}

build_pkg qrtr
pac -U --noconfirm "$(cd "$ROOT" && ls build/out/qrtr-*.pkg.tar.* | sed 's|^|/|')"
build_pkg umi-modem
build_pkg msm-firmware-loader
build_pkg umi-firmware
build_pkg umi-device

kpkg_version=$(inroot su builder -c 'cd /build/linux-xiaomi-umi && makepkg --printsrcinfo' |
	sed -n 's/^\tpkgver = //p;s/^\tpkgrel = //p' | paste -sd-)
kpkg_glob="linux-xiaomi-umi-$kpkg_version-aarch64.pkg.tar.*"
if [ -n "$KERNEL_PKG_DIR" ] && compgen -G "$KERNEL_PKG_DIR/$kpkg_glob" >/dev/null; then
	step "Using the kernel package from $KERNEL_PKG_DIR ($kpkg_version)"
	cp "$KERNEL_PKG_DIR"/$kpkg_glob "$ROOT/build/out/"
else
	build_pkg linux-xiaomi-umi
	if [ -n "$KERNEL_PKG_DIR" ]; then
		mkdir -p "$KERNEL_PKG_DIR"
		rm -f "$KERNEL_PKG_DIR"/linux-xiaomi-umi-*
		cp "$ROOT"/build/out/$kpkg_glob "$KERNEL_PKG_DIR/"
	fi
fi
ls -la "$ROOT/build/out"

step "Installing KDE Plasma and the desktop packages"
pac -S --needed --noconfirm "${PACKAGES[@]}"

step "Creating the mi10 package repository"
inroot sh -c 'cd /build/out && repo-add -q mi10.db.tar.gz ./*.pkg.tar.*'
rm -rf "$OUT/repo"
mkdir -p "$OUT/repo"
# copy the files behind repo-add's mi10.db / mi10.files links
cp -L "$ROOT"/build/out/*.pkg.tar.* "$ROOT"/build/out/mi10.{db,files}{,.tar.gz} "$OUT/repo/"
ls -la "$OUT/repo"

step "Installing the Mi 10 packages (builds boot.img through the pacman hook)"
mapfile -t LOCAL_PKGS < <(cd "$ROOT" && ls build/out/*.pkg.tar.* | sed 's|^|/|')
pac -U --noconfirm "${LOCAL_PKGS[@]}"
[ -s "$ROOT/boot/boot.img" ] || die "no /boot/boot.img: the boot image hook failed"

step "Configuring the system"
# Arch Linux ARM's default accounts: alarm/alarm and root/root
inroot userdel -r alarm 2>/dev/null || true
inroot passwd -l root
inroot useradd -m -G wheel -s /bin/bash "$USERNAME"
echo "$USERNAME:$PASSWORD" | inroot chpasswd
echo '%wheel ALL=(ALL:ALL) ALL' > "$ROOT/etc/sudoers.d/10-wheel"
chmod 440 "$ROOT/etc/sudoers.d/10-wheel"

echo mi10 > "$ROOT/etc/hostname"
sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' "$ROOT/etc/locale.gen"
inroot locale-gen
echo LANG=en_US.UTF-8 > "$ROOT/etc/locale.conf"
ln -sf /usr/share/zoneinfo/UTC "$ROOT/etc/localtime"

cat > "$ROOT/etc/fstab" <<'EOF'
# The root filesystem fills the userdata partition; it grows to the full
# partition size on the first boot (x-systemd.growfs).
PARTLABEL=userdata  /  ext4  rw,noatime,x-systemd.growfs  0 1
EOF

# SDDM: Wayland greeter with on-screen keyboard, automatic login to Plasma
mkdir -p "$ROOT/etc/sddm.conf.d"
cat > "$ROOT/etc/sddm.conf.d/10-mi10.conf" <<EOF
[General]
DisplayServer=wayland
GreeterEnvironment=QT_WAYLAND_SHELL_INTEGRATION=layer-shell
InputMethod=qtvirtualkeyboard

[Wayland]
CompositorCommand=kwin_wayland --drm --no-lockscreen --no-global-shortcuts --locale1

[Autologin]
User=$USERNAME
Session=plasma
EOF

# Plasma's on-screen keyboard for touch use without a keyboard attached
kbd=$(find "$ROOT/usr/share/applications" -name '*plasma*keyboard*.desktop' | head -n1)
if [ -n "$kbd" ]; then
	mkdir -p "$ROOT/etc/xdg"
	printf '[Wayland]\nInputMethod[$e]=%s\n' "${kbd#"$ROOT"}" > "$ROOT/etc/xdg/kwinrc"
	echo "on-screen keyboard: ${kbd#"$ROOT"}"
else
	echo "WARNING: plasma-keyboard's .desktop file not found; on-screen keyboard not set"
fi

# sshd must read sshd_config.d/, where umi-device limits it to the USB link
grep -q '^Include /etc/ssh/sshd_config.d/\*.conf' "$ROOT/etc/ssh/sshd_config" ||
	sed -i '1i Include /etc/ssh/sshd_config.d/*.conf' "$ROOT/etc/ssh/sshd_config"

# NetworkManager replaces Arch Linux ARM's systemd-networkd setup; DNS goes
# through systemd-resolved
ln -sf ../run/systemd/resolve/stub-resolv.conf "$ROOT/etc/resolv.conf"
inroot systemctl disable systemd-networkd.service systemd-networkd.socket 2>/dev/null || true
inroot systemctl enable NetworkManager.service systemd-resolved.service \
	systemd-timesyncd.service bluetooth.service sddm.service sshd.service \
	msm-firmware-loader.service umi-usb-gadget.service \
	umi-modem.service umi-modem-data.service

# Suspend has not been tested on this port: keep the phone from sleeping
# into a state it may not wake from. "systemctl unmask" these to try it.
inroot systemctl mask sleep.target suspend.target hibernate.target \
	hybrid-sleep.target suspend-then-hibernate.target

step "Cleaning up"
inroot pacman -Rns --noconfirm clang lld llvm pahole meson 2>/dev/null || true
inroot userdel -r builder 2>/dev/null || true
rm -rf "$ROOT/build" "$ROOT/etc/makepkg.conf.d/zz-mi10-build.conf"
cp "$WORK/pacman.conf.orig" "$ROOT/etc/pacman.conf"
sed -i 's/^#\?ParallelDownloads.*/ParallelDownloads = 5/' "$ROOT/etc/pacman.conf"
cat >> "$ROOT/etc/pacman.conf" <<EOF

# Xiaomi Mi 10 packages: kernel, firmware, device support. Built and published
# by github.com/miercolesvd/mi10-arch-linux; not signed, downloaded over HTTPS.
[mi10]
SigLevel = Optional TrustAll
Server = $REPO_SERVER
EOF
yes | inroot pacman -Scc >/dev/null || true
# A fresh machine-id is created on the first boot
: > "$ROOT/etc/machine-id"
rm -f "$ROOT/var/lib/systemd/random-seed"

inroot pacman -Q > "$OUT/packages.txt"
cp "$ROOT/boot/boot.img" "$OUT/boot.img"
umount "$ROOT"

step "Creating the root filesystem image"
used_mib=$(du -sxm "$ROOT" | cut -f1)
size_mib=$(( (used_mib * 12 / 10 + 1024 + 255) / 256 * 256 ))
echo "system uses ${used_mib} MiB; image size ${size_mib} MiB (grows to the full partition on the phone)"
rm -f "$WORK/rootfs.img"
truncate -s "${size_mib}M" "$WORK/rootfs.img"
mkfs.ext4 -q -L arch -b 4096 -m 1 "$WORK/rootfs.img"
mkdir -p "$WORK/mnt"
mount -o loop "$WORK/rootfs.img" "$WORK/mnt"
rsync -aHAX --numeric-ids --info=progress2 "$ROOT/" "$WORK/mnt/"
umount "$WORK/mnt"
e2fsck -fn "$WORK/rootfs.img"

step "Converting to a sparse image for fastboot"
img2simg "$WORK/rootfs.img" "$OUT/mi10-arch.img"
rm -f "$WORK/rootfs.img"

cd "$OUT"
sha256sum boot.img mi10-arch.img > SHA256SUMS
step "Done"
ls -la "$OUT"
cat SHA256SUMS
