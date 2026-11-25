#!/usr/bin/env python3
# Xiaomi Mi 10 (Arch Linux ARM): replace the Xiaomi boot logo with a Linux one.
#
#   curl -sL miercolesvd.github.io/mi10-arch-linux/bootlogo.py | sudo python3 -            # install
#   curl -sL miercolesvd.github.io/mi10-arch-linux/bootlogo.py | sudo python3 - restore    # put Xiaomi's back
#
# The "logo" partition holds 8 full-screen pictures in fixed slots. Six show
# the Mi logo (three with the "unlocked" padlock); only those six are
# replaced, each by a picture of exactly the same size and format, so the
# bootloader reads them as before. The fastboot and error screens are kept.
#
# Before the first change, the whole partition is saved to ~/logo-original.img.
# "restore" writes that copy back. From a PC, the same file also works with:
#   fastboot flash logo logo-original.img

import hashlib
import lzma
import os
import pwd
import struct
import sys
import urllib.request

PART = "/dev/disk/by-partlabel/logo"
BASE = "https://miercolesvd.github.io/mi10-arch-linux/bootlogo/"
SLOT_SIZE = 7581656  # 54-byte header + 1080 x 2340 x 3 bytes + 2
PICTURES = {
    "locked": "6437cd1dd2efcb476200cfb0d78b6f6d4ba674db3d4704094b79984916826207",
    "unlocked": "c7e5870ed52a4af5fb29020ff98cf54ccba41cfa3bd896a03ef3406e336b8ea9",
}
# offset in the partition -> picture
SLOTS = {
    0x0005000: "locked",
    0x0E7B000: "unlocked",
    0x1CF1000: "locked",
    0x242C000: "unlocked",
    0x2B67000: "locked",
    0x32A2000: "unlocked",
}


def die(msg):
    sys.exit(f"bootlogo: {msg}")


def sha(b):
    return hashlib.sha256(b).hexdigest()


def owner():
    name = os.environ.get("SUDO_USER") or "user"
    try:
        pw = pwd.getpwnam(name)
        return pw.pw_dir, pw.pw_uid, pw.pw_gid
    except KeyError:
        return os.path.expanduser("~"), 0, 0


def fetch(name):
    with urllib.request.urlopen(BASE + f"boot-{name}.bmp.xz", timeout=60) as r:
        data = lzma.decompress(r.read())
    if sha(data) != PICTURES[name]:
        die(f"downloaded picture '{name}' does not match its checksum; nothing was changed")
    return data


def is_screen_bmp(blob):
    if len(blob) < 54 or blob[:2] != b"BM":
        return False
    size = struct.unpack_from("<I", blob, 2)[0]
    w, h, _, bpp = struct.unpack_from("<iiHH", blob, 18)
    return size == SLOT_SIZE and (w, h, bpp) == (1080, 2340, 24)


def read_back(dev, off, length):
    with open(dev, "rb", buffering=0) as f:
        os.posix_fadvise(f.fileno(), 0, 0, os.POSIX_FADV_DONTNEED)  # read the flash, not the cache
        f.seek(off)
        return f.read(length)


def write_at(dev, off, blob):
    with open(dev, "r+b", buffering=0) as f:
        f.seek(off)
        f.write(blob)
        os.fsync(f.fileno())
    if read_back(dev, off, len(blob)) != blob:
        die(f"read-back at 0x{off:x} does not match. Put the original back with: ... | sudo python3 - restore")


def install(dev, home, uid, gid):
    with open(dev, "rb") as f:
        part = f.read()
    todo = []
    for off, name in SLOTS.items():
        cur = part[off:off + SLOT_SIZE]
        if sha(cur) == PICTURES[name]:
            continue
        if not is_screen_bmp(cur):
            die(f"slot at 0x{off:x} does not hold a 1080x2340 picture; this phone's logo "
                "partition is laid out differently, so nothing was changed")
        todo.append((off, name))
    if not todo:
        print("The Linux boot logo is already installed.")
        return

    backup = os.path.join(home, "logo-original.img")
    if os.path.exists(backup):
        print(f"Keeping the existing backup {backup}")
    else:
        with open(backup, "wb") as f:
            f.write(part)
        os.chown(backup, uid, gid)
        print(f"Saved the original logo partition to {backup}")

    pictures = {name: fetch(name) for name in PICTURES}
    for off, name in todo:
        write_at(dev, off, pictures[name])
        print(f"  slot 0x{off:07x}: {name} screen replaced")
    print("Done. You'll see the new logo at the next restart.")


def restore(dev, home):
    size = os.path.getsize(dev) if os.path.isfile(dev) else int(
        open(f"/sys/class/block/{os.path.basename(dev)}/size").read()) * 512
    for cand in ("logo-original.img", "partbackup/logo.img"):
        path = os.path.join(home, cand)
        if os.path.exists(path):
            break
    else:
        die(f"no backup found ({home}/logo-original.img or {home}/partbackup/logo.img)")
    with open(path, "rb") as f:
        data = f.read()
    if len(data) != size:
        die(f"{path} is {len(data)} bytes but the partition is {size}; not writing it")
    if not is_screen_bmp(data[0x5000:0x5000 + SLOT_SIZE]):
        die(f"{path} does not look like a logo partition; not writing it")
    write_at(dev, 0, data)
    print(f"Wrote {path} back to the logo partition. Xiaomi's logo returns at the next restart.")


def main():
    if os.geteuid() != 0:
        die("run it with sudo:  curl -sL miercolesvd.github.io/mi10-arch-linux/bootlogo.py | sudo python3 -")
    dev = os.path.realpath(PART)
    if not os.path.exists(dev):
        die(f"{PART} not found; is this a Xiaomi Mi 10?")
    home, uid, gid = owner()
    cmd = sys.argv[1] if len(sys.argv) > 1 else "install"
    if cmd == "install":
        install(dev, home, uid, gid)
    elif cmd == "restore":
        restore(dev, home)
    else:
        die("usage: bootlogo.py [install|restore]")


main()
