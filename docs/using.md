# Using it

## The desktop

Plasma runs on Wayland on the phone's 6.67" screen. On the first login it
turns the screen to landscape (90° counterclockwise) at 150 % scaling. To
change either, open **System Settings → Display & Monitor**.

!!! info "Images up to build-6"

    The first images started in portrait at 100 %. Set it once in Display &
    Monitor: the **fourth** Orientation button (90° counterclockwise) and
    Scale 150 %. An update to the current `umi-device` package does it for
    you on the next login (see [Updates](updates.md)).

Without a keyboard, tap a text field to bring up Plasma's on-screen keyboard.

## On a dock

![Keyboard and mouse, Ethernet, USB drives and charging work through the dock; its monitor output does not](assets/dock-setup.svg){ .diagram }

Plug the phone into any USB-C hub or dock, including Thunderbolt 3 and 4
docks.

- **Keyboard, mouse, USB drives and Ethernet** work. They show up like on
  any Linux PC; Ethernet connects through NetworkManager by itself.
- **Charging:** a dock with its own power supply charges the phone.
  An unpowered hub gets its power from the phone instead.
- **Speed:** everything shares one USB 2.0 link (480 Mbit/s), so Ethernet
  and USB drives stay well below their usual speed.
- **Monitor:** the dock's HDMI and DisplayPort outputs stay dark. The Mi 10
  wires only USB 2.0 to its USB-C port, so there is no video signal for the
  dock to pass on.

## From a PC over USB

Plugged straight into a computer (not through a dock), the phone shows up as
a USB network adapter. The phone is `172.16.42.1`, and the computer gets an
address automatically:

```sh
ssh user@172.16.42.1
```

SSH only listens on that USB link, not on Wi-Fi or Ethernet (see below to
change that).

!!! note

    The USB link is new in the Arch build and hasn't been tried on a phone
    yet. If it doesn't show up, see [Troubleshooting](troubleshooting.md).

## SSH over Wi-Fi or Ethernet

Change the default password first (`passwd`): anyone on the same network
could otherwise log in with `147147`. Then one line in Konsole:

```sh
curl -sL miercolesvd.github.io/mi10-arch-linux/ssh.sh | sudo sh
```

It opens SSH on every network and prints the exact `ssh user@…` line to use
from your computer. To go back to the USB cable only:

```sh
curl -sL miercolesvd.github.io/mi10-arch-linux/ssh.sh | sudo sh -s off
```

??? note "What the script does"

    It comments out the `ListenAddress` line in
    `/etc/ssh/sshd_config.d/50-umi-usb.conf` and restarts `sshd`
    ([read it](ssh.sh)). An edited file stays as you left it through
    updates; a deleted one would come back with the next `umi-device` update.

Logging in with a key is safer than a password:

```sh
ssh-copy-id user@<address>      # on the computer, once
```

After that, you can turn password logins off on the phone:

```sh
echo 'PasswordAuthentication no' | sudo tee /etc/ssh/sshd_config.d/60-keys-only.conf
sudo systemctl restart sshd
```

## Networks

- **Wi-Fi and Bluetooth:** Plasma's network and Bluetooth icons in the panel,
  as on any Plasma desktop.
- **Mobile data (4G/5G):** with a SIM card, the modem starts at boot and
  mobile data comes up by itself when no other connection is active. It runs
  outside NetworkManager, so Plasma doesn't show it. Calls and SMS are not set
  up.

## Sound

Both loudspeakers play in stereo and the internal microphones work, through
PipeWire. Wired headsets (USB-C audio adapters) and the earpiece for calls
don't work yet.

## Battery

The phone charges from a charger or a powered dock.

!!! bug "Shows "Discharging" while charging"

    The battery status can say *Discharging* even though the charge level
    goes up. It's a reporting bug in the charger driver and is being looked
    into; charging itself works.

## Suspend

Suspend has never been tried on this port, so it's switched off: the phone
can't go to sleep in a state it might not wake from. To try it anyway:

```sh
sudo systemctl unmask sleep.target suspend.target
```

## Installing software

It's Arch Linux ARM: `sudo pacman -S <package>`. Packages have to be built
for `aarch64`; most of the Arch repositories are. Flatpak works too after
`sudo pacman -S flatpak`.

To see which kernel and device packages you have:

```sh
pacman -Q linux-xiaomi-umi umi-device umi-firmware
```

## Boot logo

The phone still shows Xiaomi's logo while it starts. To replace it with a
Linux one:

```sh
curl -sL miercolesvd.github.io/mi10-arch-linux/bootlogo.py | sudo python3 -
```

![The replacement boot screens: normal and with the unlocked-bootloader padlock](assets/bootlogo.png){ width="360" }

The `logo` partition holds 8 pictures; the script replaces the six with the
Mi logo, each with a picture of exactly the same size and format. The padlock
on the unlocked screens stays: it's the bootloader's warning that the phone
is unlocked. The fastboot and error screens are kept as they are.

Before changing anything, it saves the partition to `~/logo-original.img`.
Xiaomi's logo comes back with:

```sh
curl -sL miercolesvd.github.io/mi10-arch-linux/bootlogo.py | sudo python3 - restore
```

or, from a PC, `fastboot flash logo logo-original.img`.
[Read the script](bootlogo.py) first if you like.

## The phone's other partitions

Arch Linux lives on `userdata`. The phone's flash has over 100 other
partitions: firmware, calibration data, MIUI's own system (in `super`), the
modem's storage and more. They're hidden from Dolphin, because one click there
would mount them read-write. To look at them read-only:

```sh
curl -sL miercolesvd.github.io/mi10-arch-linux/parts.sh | sudo sh
```

Every partition with a filesystem appears under `/mnt/p/<name>`. Nothing on
them changes: the mounts are read-only and ext4 journals aren't replayed.
Unmount them again with `... | sudo sh -s umount`.

!!! warning "Back them up before experimenting with the modem"

    `modemst1`, `modemst2`, `fsg` and the `mdm1m9kefs*` partitions hold the
    modem's own data, including the IMEI, and the modem writes to them while
    it runs. A damaged copy can mean no mobile network. This copies every
    partition except `super` and `userdata` to `~/partbackup`:

    ```sh
    curl -sL miercolesvd.github.io/mi10-arch-linux/parts.sh | sudo sh -s backup
    ```

    Then copy the folder to another computer. Don't share it: it contains
    your IMEI, Wi-Fi and Bluetooth addresses and device keys.

[Read the script](parts.sh) first if you like.
