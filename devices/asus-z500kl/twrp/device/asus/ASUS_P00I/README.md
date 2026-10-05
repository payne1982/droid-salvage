# TWRP device tree — ASUS ZenPad 3S 10 LTE (Z500KL / P00I)

This directory belongs at `device/asus/ASUS_P00I` inside a TWRP `twrp-9.0` minimal
manifest checkout. The name has to be exactly `ASUS_P00I`, because the build system
matches it against the device's `ro.product.device`.

Build and flash instructions, and the reasoning behind every non-obvious line in here,
are two levels up:

- [`../../../../README.md`](../../../../README.md) — status, building, flashing
- [`../../../../NOTES.md`](../../../../NOTES.md) — why each piece is needed

Before building, fetch the vendor pieces from your own tablet — none of them are
committed:

```sh
./tools/extract-from-device.sh
```

Started from [twrpdtgen](https://github.com/twrpdtgen/twrpdtgen) output, then reworked:
raw `mmcblk0pN` nodes instead of `by-name` symlinks, a fix for the digitiser, a rebuilt
`/dev/block/bootdevice` tree, the Nougat `property_contexts`, and the two board
properties that make `vold` load the real keymaster.

On the kernel in `prebuilt/`, there are two routes:

- **build it** from ASUS' sources — see [`../../../kernel/`](../../../kernel/). The
  digitiser fix is one of the patches there, so nothing else has to be done to it, and
  you do not need a working tablet to obtain a kernel.
- **take the stock one** off your own tablet, which is what
  `tools/extract-from-device.sh` does, and then let `tools/patch-kernel.py` rewrite 3
  bytes of it. That script finds the site by scanning for code rather than at a fixed
  offset, so it works on a kernel you built as well — but if you built it from the
  sources above, the fix is already in and running it would be wrong.
