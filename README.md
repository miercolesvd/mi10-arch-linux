# Arch Linux ARM on the Xiaomi Mi 10

Arch Linux ARM with the KDE Plasma desktop (Wayland) for the Xiaomi Mi 10
(`umi`, Snapdragon 865). A full desktop system with `pacman`, not a phone
shell: plug the phone into a USB-C hub or dock for keyboard, mouse and
Ethernet, and use the phone's own screen as the display.

The kernel is the close-to-mainline 6.12 LTS kernel of the
[Nura port](https://github.com/miercolesvd/mi10-port) (from the
[umi-mainline](https://github.com/colorgarden/umi-mainline) bring-up), plus
one patch that makes the USB-C port dual role. Everything else is stock Arch
Linux ARM.

## Status

**Boots and runs KDE Plasma on the phone** (release build-6, 25 Nov 2026).
The hardware support is the Nura port's, where these work: display
(60/90 Hz), touch, GPU (OpenGL 4.6, Vulkan 1.3), Wi-Fi, Bluetooth, both
loudspeakers, internal microphones, modem with mobile data, battery and
charging.

| | |
|---|---|
| Plasma desktop on the phone's screen | **works** (25 Nov 2026) |
| USB-C host mode with a Thunderbolt 4 dock: keyboard, mouse, Ethernet | **works** (kernel patch 0015; 25 Nov 2026) |
| Monitor on the dock's HDMI/DisplayPort | **not possible**: the Mi 10 wires only USB 2.0 to the port, no DisplayPort |
| Wired headsets, earpiece for calls, sensors, cameras | not working |
| Suspend | not tested, so it is turned off (see below) |

Only phones with the CSOT panel and ST FTS touch are supported, as in the
Nura port.

## Install

**This erases everything on the phone's `userdata` partition** (Android or
Nura data). The bootloader must be unlocked; the `dtbo` partition stays
stock.

1. Download all files of the newest [release](../../releases) and put the
   system image back together:

   ```sh
   cat mi10-arch.img.zst.part* | zstd -d -o mi10-arch.img
   sha256sum -c SHA256SUMS
   ```

2. Phone off, hold volume down + power until FASTBOOT shows, connect USB:

   ```sh
   fastboot flash userdata mi10-arch.img   # takes a few minutes
   fastboot flash boot boot.img
   fastboot boot boot.img                  # not "fastboot reboot"
   ```

   Right after flashing, `fastboot reboot` drops back into fastboot instead
   of starting the new system, so start it with `fastboot boot` once. After
   that, normal restarts boot Arch.

3. The first boot takes longer while the file system grows to fill the
   partition. Plasma starts logged in as `user` (password `147147`). Change
   the password right away: open Konsole and run `passwd`.

Without a keyboard, tap a text field to get Plasma's on-screen keyboard.

## Using it as a desktop

- **Dock or hub:** plug it in and keyboard, mouse, storage and Ethernet work.
  A powered dock also charges the phone. Everything shares one USB 2.0 link
  (480 Mbit/s).
- **Landscape:** the first login turns the phone's screen to landscape
  (90° counterclockwise) at 150 % scaling. Change it any time in System
  Settings > Display & Monitor.
- **From a PC over USB:** the phone is `172.16.42.1` on the USB cable;
  `ssh user@172.16.42.1`. SSH only listens there, not on Wi-Fi (delete
  `/etc/ssh/sshd_config.d/50-umi-usb.conf` to change that).
- **Suspend** is masked because it has never been tried on this port. To try
  it: `sudo systemctl unmask sleep.target suspend.target`.

## Updates

`sudo pacman -Syu` as on any Arch system. The Mi 10 packages (kernel,
firmware, device support) come from this project's own pacman repository,
`mi10`, which every build publishes as the
[`packages` release](../../releases/tag/packages).

Installs from build-6 don't have that repository yet. Add it once:

```sh
sudo tee -a /etc/pacman.conf <<'EOF'

[mi10]
SigLevel = Optional TrustAll
Server = https://github.com/miercolesvd/mi10-arch-linux/releases/download/packages
EOF
sudo pacman -Syu
```

The packages are not signed; pacman downloads them over HTTPS from GitHub.

When the kernel, firmware or initramfs change, a pacman hook runs
`umi-update-boot`, which builds a new boot image (`/boot/boot.img`, previous
one kept as `/boot/boot.img.old`) and writes it to the `boot` partition. Run `sudo umi-update-boot` to do that by
hand, for example after editing the kernel command line in
`/etc/kernel/cmdline`.

If the phone no longer boots after an update: fastboot mode, then
`fastboot boot boot.img` with the previous image from a release (or a copy of
`/boot/boot.img.old`), and once it is up, `sudo umi-update-boot`.

## Building

`.github/workflows/build.yml` builds everything on GitHub's free arm64
runner and publishes a release, on every push that changes `pkgbuilds/` or
`build/`, or by hand under Actions > Build image > Run workflow. The kernel
takes about an hour on that runner and is cached until its files change. To
build on a faster machine, set the `RUNNER` repository variable (for example
`ubicloud-standard-30-arm`).

On an arm64 Linux machine with `arch-install-scripts`, `libarchive-tools`,
`gpgv`, `e2fsprogs`, `rsync` and `img2simg`:

```sh
sudo build/build-image.sh out/
```

The script downloads Arch Linux ARM (signature checked against
`build/archlinuxarm-builder.asc`), builds the packages below in a chroot,
installs the packages in `build/packages.txt`, and writes `boot.img` and the
sparse `mi10-arch.img` to `out/`.

## Layout

```
pkgbuilds/
  linux-xiaomi-umi/     kernel 6.12.94 + 15 patches + config
  umi-device/           boot image hook, initramfs hook, panel, sound, USB link
  umi-firmware/         Adreno 650 firmware (zap shader signed for this phone)
  umi-modem/            SDX55M modem start-up and mobile data
  msm-firmware-loader/  loads ADSP and modem firmware from the phone's partitions
  qrtr/                 QRTR library for the modem tools (not in the Arch repos)
build/
  build-image.sh        builds the whole system image
  packages.txt          desktop and app packages
```

## Credits and licenses

Kernel patches 0001–0014 and the hardware fixes come from the Nura port and
the umi-mainline bring-up; the kernel and its patches are GPL-2.0.
msm-firmware-loader (MIT) is postmarketOS/Nura's; qrtr and tqftpserv
(BSD-3-Clause) are linux-msm's. The modem tools are GPL-2.0. The Adreno
firmware is proprietary Qualcomm/Xiaomi firmware, redistributed as in the
umi-mainline repository. Scripts and configuration in this repository are
MIT.
