# Building

## On GitHub

`.github/workflows/build.yml` builds everything on GitHub's free arm64
runner. It runs on every push that changes `pkgbuilds/` or `build/`, or by
hand under **Actions → Build image → Run workflow**. Each run publishes:

- a `build-N` release with `boot.img`, the system image, `SHA256SUMS` and
  `packages.txt`;
- the Mi 10 packages to the `packages` release, which is the `mi10` pacman
  repository installed phones update from.

The kernel takes about an hour on the free runner. The built kernel package
is cached until something under `pkgbuilds/linux-xiaomi-umi/` changes, so
other builds take about 10 minutes.

To build on a faster machine, set the repository variable `RUNNER`
(Settings → Secrets and variables → Actions → Variables), for example to
`ubicloud-standard-30-arm`. The default user password can be set with the
secret `UMI_PASSWORD`.

## On your own machine

You need an arm64 Linux machine (or VM) and root:

```sh
sudo apt install arch-install-scripts libarchive-tools gpgv e2fsprogs \
    rsync android-sdk-libsparse-utils
sudo build/build-image.sh out/
```

The script downloads Arch Linux ARM (checking its signature against
`build/archlinuxarm-builder.asc`), builds the packages in a chroot,
installs the desktop from `build/packages.txt`, and writes `boot.img`,
`mi10-arch.img` and the `repo/` directory to `out/`.

## Layout

```
pkgbuilds/
  linux-xiaomi-umi/     kernel 6.12.94, 16 patches, config
  umi-device/           boot image hook, initramfs hook, panel, sound,
                        USB link, display defaults
  umi-firmware/         Adreno 650 firmware (zap shader signed for this phone)
  umi-modem/            SDX55M modem start-up and mobile data
  msm-firmware-loader/  loads ADSP and modem firmware from the phone's partitions
  qrtr/                 QRTR library for the modem tools
build/
  build-image.sh        builds the whole image
  packages.txt          desktop and app packages
docs/                   this site (MkDocs Material)
```

## Kernel patches

| Patch | What it does |
|---|---|
| 0001–0014 | Mi 10 bring-up from the Nura port: panel, touch, charger and fuel gauge, device tree, sound amplifiers, ADSP firmware, modem |
| 0015 | USB-C port dual role: host for hubs and docks, device for a PC |
| 0016 | panel brightness sent high byte first, so the whole range works |

## This site

The documentation is in `docs/` and builds with MkDocs Material; pushing a
change under `docs/` publishes it. To preview locally:

```sh
pip install -r docs/requirements.txt
mkdocs serve
```
