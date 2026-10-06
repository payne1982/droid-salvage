#!/usr/bin/env python3
"""Pull the init scripts out of an Android boot image, with nothing but the standard
library.

magiskboot would do this too, but it is an arm64 Android binary: it does not run on an
x86_64 build host, and it segfaults on a Raspberry Pi. The boot header is simple enough
that parsing it here removes a dependency instead of adding one.

usage: unpack-boot-ramdisk.py <boot.img> <destination dir> [name ...]
       with no names, every entry is extracted.
"""
import gzip, io, os, struct, sys

def ramdisk_of(path):
    d = open(path, "rb").read()
    if d[:8] != b"ANDROID!":
        sys.exit(f"{path}: not an Android boot image")
    kernel_sz, _, ramdisk_sz, _ = struct.unpack_from("<IIII", d, 8)
    pagesize = struct.unpack_from("<I", d, 8 + 7 * 4)[0]
    pad = lambda n: (n + pagesize - 1) // pagesize * pagesize
    off = pagesize + pad(kernel_sz)
    blob = d[off:off + ramdisk_sz]
    if blob[:2] == b"\x1f\x8b":
        return gzip.decompress(blob)
    sys.exit("ramdisk is not gzip; lz4 and lzma are not handled here")

def cpio_entries(buf):
    """newc format. Yields (name, mode, data)."""
    i = 0
    while buf[i:i + 6] == b"070701":
        f = [int(buf[i + 6 + n * 8: i + 6 + (n + 1) * 8], 16) for n in range(13)]
        mode, fsize, nsize = f[1], f[6], f[11]
        name = buf[i + 110: i + 110 + nsize - 1].decode(errors="replace")
        hstart = (i + 110 + nsize + 3) & ~3
        if name == "TRAILER!!!":
            return
        yield name, mode, buf[hstart:hstart + fsize]
        i = (hstart + fsize + 3) & ~3

def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    img, dest, wanted = sys.argv[1], sys.argv[2], set(sys.argv[3:])
    os.makedirs(dest, exist_ok=True)
    n = 0
    for name, mode, data in cpio_entries(ramdisk_of(img)):
        if wanted and name not in wanted:
            continue
        if not (mode & 0o170000) == 0o100000:      # regular files only
            continue
        out = os.path.join(dest, os.path.basename(name))
        with open(out, "wb") as fh:
            fh.write(data)
        os.chmod(out, mode & 0o777)
        n += 1
        print(f"    {name}")
    print(f"  {n} file(s)")
    if wanted and n != len(wanted):
        missing = wanted - {os.path.basename(p) for p in os.listdir(dest)}
        if missing:
            print(f"  not in this ramdisk: {' '.join(sorted(missing))}", file=sys.stderr)

main()
