#!/usr/bin/env python3
"""Patch the stock ASUS Z500KL Image.gz-dtb so touch works in recovery.

LK always appends "androidboot.mode=recovery" to the cmdline when it boots the
recovery partition. ASUS' start_kernel() turns that into entry_mode=2, and the
tail of mxt_probe() (atmel_z500 driver, source line 6163) then does:

    if (entry_mode != 1) {
            msleep(1000);
            mxt_set_t7_power_cfg(data, MXT_POWER_CFG_DEEPSLEEP);
            touch_ic_status = false;
            return 0;
    }

With touch_ic_status false the IRQ handler drops every touch event, so the
digitiser is dead in recovery. Patching entry_mode itself breaks the boot: the
charger/display/sensor drivers branch on it too. Instead this turns the probe's
"b.eq <epilogue>" into an unconditional branch, so only mxt_probe skips that
block. Android is unaffected (there entry_mode is already 1, so the block was
skipped anyway).

usage: patch-kernel.py <stock Image.gz-dtb> <output Image.gz-dtb>
"""
import gzip
import struct
import sys
import zlib

FDT_MAGIC = b"\xd0\x0d\xfe\xed"
NEEDLE = b" ATMEL Touch DEEPSLEEP ... \n\0"


def u32(b, o):
    return struct.unpack_from("<I", b, o)[0]


def find_literal(img, needle):
    o = img.index(needle)
    return img.rfind(b"\0", 0, o) + 1


def adrp_add_refs(img, target):
    """offsets of adrp/add pairs whose resolved address is `target`"""
    out = []
    for off in range(0, len(img) - 4, 4):
        w = u32(img, off)
        if (w & 0x9F000000) != 0x90000000:  # adrp
            continue
        rd = w & 0x1F
        imm = (((w >> 5) & 0x7FFFF) << 2) | ((w >> 29) & 3)
        if imm >= (1 << 20):
            imm -= 1 << 21
        page = (off & ~0xFFF) + (imm << 12)
        for k in range(1, 9):
            w2 = u32(img, off + 4 * k)
            if (w2 & 0xFF800000) == 0x91000000 and (w2 & 0x1F) == rd and ((w2 >> 5) & 0x1F) == rd:
                if page + ((w2 >> 10) & 0xFFF) == target:
                    out.append(off)
                break
    return out


def locate_probe_branch(img):
    """offset of the `b.eq epilogue` guarding the deep-sleep block in mxt_probe"""
    lit = find_literal(img, NEEDLE)
    sites = []
    for ref in adrp_add_refs(img, lit):
        # the probe copy is the one that stores touch_ic_status = false right after
        # the printk: strb wzr, [xN, #imm]  ->  0x39000000 | imm12<<10 | Rn<<5 | 31
        if any((u32(img, ref + 4 * k) & 0xFFC0001F) == 0x3900001F
               for k in range(2, 6)):
            sites.append(ref)
    assert len(sites) == 1, f"expected 1 probe site, found {sites}"
    site = sites[0]

    for back in range(1, 24):
        off = site - 4 * back
        w = u32(img, off)
        if (w & 0xFF00001F) != 0x54000000:  # b.eq
            continue
        cmp_w = u32(img, off - 4)
        assert (cmp_w & 0xFFC0001F) == 0x7100001F and ((cmp_w >> 10) & 0xFFF) == 1, \
            f"insn before b.eq at {off:#x} is not `cmp wN, #1` ({cmp_w:#010x})"
        return off
    raise AssertionError("no b.eq found above the deep-sleep block")


src, dst = sys.argv[1], sys.argv[2]
blob = open(src, "rb").read()

d = zlib.decompressobj(16 + zlib.MAX_WBITS)
img = bytearray(d.decompress(blob))
dtbs = d.unused_data
assert dtbs[:4] == FDT_MAGIC, "no appended DTB after the gzip stream"

off = locate_probe_branch(img)
old = u32(img, off)
imm19 = (old >> 5) & 0x7FFFF
new = 0x14000000 | imm19  # b <same target>
struct.pack_into("<I", img, off, new)
print(f"mxt_probe guard at {off:#x}: {old:#010x} (b.eq +{imm19}) -> {new:#010x} (b +{imm19})")

out = gzip.compress(bytes(img), compresslevel=9, mtime=0) + dtbs
open(dst, "wb").write(out)
print(f"Image {len(img)} bytes, output {len(out)} bytes, {len(dtbs)} bytes of DTB kept")
