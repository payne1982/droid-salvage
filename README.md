# droid-salvage

Bringing abandoned Android devices back into use: custom recoveries, kernel patches
and the notes that explain *why* each piece was needed.

The write-ups matter as much as the code here. Most of the work on an old device is not
writing a device tree, it is finding out which of a hundred small assumptions the stock
firmware makes is no longer true. Those findings are recorded next to the code.

## Layout

```
devices/<vendor>-<model>/
├── README.md     what works, how to build it, how to flash it
├── NOTES.md      the technical findings, in enough detail to be reproduced
├── ROADMAP.md    where a device is going, and how each step went
├── kernel/       patches and tools to build the kernel from the vendor's sources
├── twrp/         mirrors an AOSP tree, so it can be copied in as-is
│   └── device/<vendor>/<CODENAME>/
└── rom/          the same, for a ROM tree
    └── device/<vendor>/<CODENAME>/
```

`<vendor>-<model>` is lowercase and hyphenated, using the **commercial model number**,
because that is what people search for. The build system needs a different name: the
inner `<CODENAME>` must match the device's `ro.product.device` exactly. Both are stated
at the top of each device's README.

## Devices

| device | status |
|---|---|
| [asus-z500kl](devices/asus-z500kl) — ASUS ZenPad 3S 10 LTE (Z500KL / P00I) | TWRP 3.7 released: touch, all partitions, FDE decryption of `/data`, adb. LineageOS 16.0 (Android 9) working, SELinux enforcing, nearly ready for a first release. Kernel built from ASUS' sources |

## Local settings

Nothing in this repository refers to a particular machine, address or device serial.
Copy `local.conf.example` to `local.conf` (which is git-ignored) and put yours there.

## Branches

- `V1_DEV` — work in progress
- `V1` — what has been tested on hardware

## A word on vendor files

No vendor binaries are committed: no kernels, no firmware blobs, no stock init files.
Each device tree ships a script that extracts them from your own tablet. This keeps the
repository small and legally tidy, and it means the committed tree builds the exact
image that is published, so anyone can reproduce it byte for byte.
