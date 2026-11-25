#!/usr/bin/env python3
# Xiaomi Mi 10 (Arch Linux ARM): pull the boot screen images out of the
# "logo" and "splash" partitions, read-only.
#
#   curl -sL miercolesvd.github.io/mi10-arch-linux/logo.py | sudo python3 -
#
# The images go to ~/Pictures/boot-logo (open them in Gwenview), with
# report.txt describing where each one sits in its partition.
#
# Finds BMP and PNG images anywhere in the partitions, and Qualcomm
# "SPLASH!!" images (raw or run-length encoded), which are converted to BMP.

import os
import pwd
import struct
import sys
import zlib

PARTS = ["logo", "splash"]


def owner():
    name = os.environ.get("SUDO_USER") or "user"
    try:
        pw = pwd.getpwnam(name)
        return pw.pw_dir, pw.pw_uid, pw.pw_gid
    except KeyError:
        return os.path.expanduser("~"), os.getuid(), os.getgid()


def read_part(name):
    for path in (f"/dev/disk/by-partlabel/{name}",):
        if os.path.exists(path):
            with open(path, "rb") as f:
                return f.read()
    return None


def bmp_at(data, off):
    """Return (size, width, height, bpp) if a plausible BMP starts at off."""
    if len(data) - off < 54:
        return None
    size, r1, r2, pix = struct.unpack_from("<IHHI", data, off + 2)
    dib, w, h, planes, bpp = struct.unpack_from("<IiiHH", data, off + 14)
    if r1 or r2 or planes != 1 or bpp not in (1, 4, 8, 16, 24, 32):
        return None
    if dib not in (12, 40, 52, 56, 108, 124):
        return None
    if not (0 < w <= 8192 and 0 < abs(h) <= 8192):
        return None
    if not (14 + dib <= pix < size <= len(data) - off):
        return None
    row = ((w * bpp + 31) // 32) * 4
    if size - pix < row * abs(h) * 0.9:  # allow a little slack in the header
        return None
    return size, w, h, bpp


def png_at(data, off):
    """Return the length of a PNG starting at off, by walking its chunks."""
    p = off + 8
    while p + 12 <= len(data):
        n, kind = struct.unpack_from(">I4s", data, p)
        if n > len(data) - p - 12 or not kind.isalpha():
            return None
        p += 12 + n
        if kind == b"IEND":
            w, h = struct.unpack_from(">II", data, off + 16)
            return p - off, w, h
    return None


def bmp_bytes(w, h, rgb_rows):
    """24-bit bottom-up BMP from top-down rows of BGR bytes."""
    row = ((w * 3 + 3) // 4) * 4
    pad = b"\0" * (row - w * 3)
    body = b"".join(r + pad for r in reversed(rgb_rows))
    head = struct.pack("<2sIHHI", b"BM", 54 + len(body), 0, 0, 54)
    head += struct.pack("<IiiHHIIiiII", 40, w, h, 1, 24, 0, len(body), 2835, 2835, 0, 0)
    return head + body


def splash_at(data, off):
    """Decode a Qualcomm SPLASH!! image: 512-byte header, then raw or RLE24 BGR."""
    w, h, kind, blocks = struct.unpack_from("<IIII", data, off + 8)
    if not (0 < w <= 8192 and 0 < h <= 8192) or kind not in (0, 1):
        return None
    start, end = off + 512, off + 512 + blocks * 512
    src = data[start:end]
    px = bytearray()
    want = w * h * 3
    if kind == 0:
        px = src[:want]
    else:
        i = 0
        while len(px) < want and i < len(src):
            c = src[i]
            i += 1
            if c & 0x80:  # run: one pixel repeated (c & 0x7f) + 1 times
                px += src[i:i + 3] * ((c & 0x7F) + 1)
                i += 3
            else:  # literal: c + 1 pixels
                px += src[i:i + 3 * (c + 1)]
                i += 3 * (c + 1)
    if len(px) < want:
        return None
    rows = [bytes(px[y * w * 3:(y + 1) * w * 3]) for y in range(h)]
    return w, h, kind, blocks, bmp_bytes(w, h, rows)


def main():
    if os.geteuid() != 0:
        sys.exit("Run it with sudo:  curl -sL miercolesvd.github.io/mi10-arch-linux/logo.py | sudo python3 -")
    home, uid, gid = owner()
    out = os.path.join(home, "Pictures", "boot-logo")
    os.makedirs(out, exist_ok=True)
    report = []
    files = []

    for part in PARTS:
        data = read_part(part)
        if data is None:
            report.append(f"{part}: partition not found")
            continue
        used = len(data.rstrip(b"\0"))
        report.append(f"{part}: {len(data)} bytes, data up to 0x{used:x}")
        report.append(f"  starts with: {data[:32].hex(' ')}  {data[:16]!r}")
        if used == 0:
            report.append("  (empty)")
            continue
        n = 0

        off = data.find(b"BM")
        while off != -1:
            info = bmp_at(data, off)
            if info:
                size, w, h, bpp = info
                n += 1
                name = f"{part}-{n:02d}-at-0x{off:x}-{w}x{abs(h)}.bmp"
                files.append((name, data[off:off + size]))
                report.append(f"  BMP    0x{off:08x}  {size:9d} bytes  {w}x{abs(h)}  {bpp}-bit  -> {name}")
                off = data.find(b"BM", off + size)
            else:
                off = data.find(b"BM", off + 1)

        off = data.find(b"\x89PNG\r\n\x1a\n")
        while off != -1:
            info = png_at(data, off)
            if info:
                size, w, h = info
                n += 1
                name = f"{part}-{n:02d}-at-0x{off:x}-{w}x{h}.png"
                files.append((name, data[off:off + size]))
                report.append(f"  PNG    0x{off:08x}  {size:9d} bytes  {w}x{h}  -> {name}")
                off = data.find(b"\x89PNG\r\n\x1a\n", off + size)
            else:
                off = data.find(b"\x89PNG\r\n\x1a\n", off + 1)

        off = data.find(b"SPLASH!!")
        while off != -1:
            info = splash_at(data, off)
            if info:
                w, h, kind, blocks, bmp = info
                n += 1
                name = f"{part}-{n:02d}-at-0x{off:x}-{w}x{h}.bmp"
                files.append((name, bmp))
                enc = "RLE24" if kind else "raw"
                report.append(f"  SPLASH 0x{off:08x}  {blocks * 512 + 512:9d} bytes  {w}x{h}  {enc}  -> {name}")
            else:
                report.append(f"  SPLASH 0x{off:08x}  (header not understood: {data[off:off + 32].hex(' ')})")
            off = data.find(b"SPLASH!!", off + 8)

        if n == 0:
            report.append("  no images recognised")
        # The header, for working out the layout
        words = struct.unpack_from("<64I", data, 0)
        report.append("  first 64 words: " + " ".join(f"{x:x}" for x in words))

    for name, blob in files:
        path = os.path.join(out, name)
        with open(path, "wb") as f:
            f.write(blob)
        os.chown(path, uid, gid)
    text = "\n".join(report) + "\n"
    path = os.path.join(out, "report.txt")
    with open(path, "w") as f:
        f.write(text)
    os.chown(path, uid, gid)
    for d in (out, os.path.dirname(out)):
        os.chown(d, uid, gid)
    print(text)
    print(f"{len(files)} images saved to {out}")


main()
