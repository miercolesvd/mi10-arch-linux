# Troubleshooting

## The screen stays black after flashing

- Wait a full minute: the first boot resizes the file system.
- Plug the phone straight into a computer and try
  `ssh user@172.16.42.1`. If that works, the system runs and only the
  screen is the problem; collect the logs below.
- A phone with the Samsung panel or Goodix touch is not supported (see
  [Hardware status](hardware.md#supported-variant)).

## The phone goes back into fastboot after flashing

Start it once with `fastboot boot boot.img` instead of `fastboot reboot`.
Later restarts boot normally.

## `sudo` refuses the right password

After 3 wrong passwords, the account is locked for 10 minutes. Wait, then
type the password once. The default is `147147`, typed on the number row or
with Num Lock on. Once you're in, you can clear the counter at any time:

```sh
sudo faillock --user user --reset
```

There is no root password: use `sudo -i`.

## Brightness is either full or almost black

Images up to build-6 send the brightness level in the wrong byte order.
Update (see [Updates](updates.md)) and restart.

## Battery says "Discharging" while plugged in

A known reporting bug; the phone still charges. Check the real state with:

```sh
grep . /sys/class/power_supply/*/{status,online,current_now,capacity} 2>/dev/null
```

## The dock's monitor stays dark

Expected: the Mi 10 has no video output on its USB-C port. Everything else
on the dock works.

## The phone doesn't start after an update

See [Updates → If the phone doesn't start](updates.md#if-the-phone-doesnt-start-after-an-update).

## Collecting logs for a bug report

One line in Konsole:

```sh
curl -sL miercolesvd.github.io/mi10-arch-linux/diag.sh | sudo sh
```

It writes `mi10-diag.txt` to your home folder: modem start-up, battery and
charger state, and kernel messages. It only reads, it changes nothing.
([Read the script](diag.sh) first if you like.)

For everything else:

```sh
journalctl -b > journal.txt          # this boot
sudo dmesg > dmesg.txt               # kernel messages
```

Attach the files to an
[issue](https://github.com/miercolesvd/mi10-arch-linux/issues).
