# LineageOS 20 for ASUS_P00I

Android 13 on the ZenPad 3S 10 LTE. LineageOS 20 from the
[LineageOS-UL](https://github.com/LineageOS-UL) manifest, which keeps it running on
kernels without eBPF, with a device tree written for this tablet, a kernel built from
ASUS' 3.10 sources and the Nougat vendor blobs taken off your own tablet. It runs as a
daily tablet with SELinux enforcing, at the Android security patch level of February
2026. The image, `payne_32`, is on the
[Releases](https://github.com/payne1982/droid-salvage/releases) page.

It replaces LineageOS 16 (Android 9), whose image `payne_31` stays on the same page and
whose page is now [README-LOS16.md](README-LOS16.md). 16 is not worked on any more.

- **what the hardware is, and where each piece comes from:** [HARDWARE.md](HARDWARE.md)
- **the kernel:** [../kernel/](../kernel/) — ASUS' sources, with what Android 13 needs
  from newer kernels brought back to 3.10
- **how it was built, problem by problem:** [BUILDING-LOS20.md](BUILDING-LOS20.md)
- **how it came about:** [../ROADMAP.md](../ROADMAP.md)

## What works

Every item below has been checked on the tablet, under SELinux enforcing, on the
builds that led to this image; the image itself was installed over the last of them
and checked for what it adds.

| | |
|---|---|
| display, touch, the magnetic cover | yes — the display hardware composes the layers, as on stock |
| audio: speaker, microphone, wired headset and its microphone | yes — music is decoded by the DSP (checked with MP3) |
| Wi-Fi | yes — and it reconnects by itself with the screen off |
| Bluetooth, with audio | yes — headphones, in AAC |
| sensors | yes |
| hardware video decoding: H.264, HEVC (up to 4K), MPEG-4, VP8, VP9 | yes, at 30 frames a second |
| hardware video encoding (camera recording, screen recording) | yes |
| cameras, rear and front: photos and video | yes — see *Known* for Aperture |
| GPS | yes — first fix outdoors in 15 s |
| mobile network with a SIM: the PIN, data on LTE, SMS in both directions, airplane mode | yes — **no voice calls**, see below |
| microSD, exFAT included (a 256 GB card) | yes — as portable storage; ejected, taken out and put back |
| USB: adb with on-screen authorisation, file transfer (MTP) to a Windows PC | yes |
| charging: from a computer, from a Quick Charge 3 adapter at 9 V, with the system off | yes — with the system off it shows the level and starts Android when the power key is held |
| standby | yes — one night unplugged, eight hours: about 1% of the battery |
| the time across a restart without a network | yes |
| DRM: Widevine level 3 | yes — provisioned by Google's server |
| a PIN on the lock screen, asked for again after a restart | yes |
| Google apps | yes, with MindTheGapps; see below |

Not there:

- **Voice calls.** The modem turns them down by itself, as on 16 and as on stock, which
  had no dialer; [README-LOS16.md](README-LOS16.md) has what was found. There is no Phone
  app. That includes emergency numbers: do not count on this tablet to call one.
- **Widevine level 1.** Level 3 works; streaming services usually give it standard
  definition. Why level 1 cannot be had is in README-LOS16.md, and nothing about it
  changed with 20.
- **Encryption of `/data`.** Android 13 no longer has the full-disk kind, and the
  file-based kind needs kernel support a 3.10 does not have. `/data` is not encrypted:
  whoever has the tablet and a recovery can read it.

Known, and left as they are:

- Scrolling in heavy apps is not perfectly smooth, though without tearing or visible
  slowdowns. Apps from the Play Store start out uncompiled; Android compiles them while
  the tablet charges and is idle, and they run better from then on.
- Photos taken in Aperture, LineageOS' camera, come out turned by 90 degrees when the
  screen's rotation is locked in landscape. With rotation left automatic they come out
  the right way up; Open Camera gets them right either way.
- On the setup wizard's Wi-Fi page the word "Internet" is cut short.
- Once, after the cable came out, the tablet could not suspend for a quarter of an
  hour. It has not happened again, and why it did is not known.

Not tested yet — none of these is known to be broken, and none is known to work:

- **Wi-Fi hotspot and USB tethering.**
- **USB OTG**: sticks, keyboards, mice.
- **MMS.**
- **Data Saver and mobile data limits.** The kernel has no eBPF, and the network rules
  Android 13 enforces them with refer to eBPF programs, so they are not installed.
  Whether the limits still apply has not been looked at.
- **the other USB modes** in the notification: PTP, MIDI.
- **a card formatted NTFS.**
- **screen casting** (Miracast).

## Installing

You need the [TWRP for this tablet](../README.md) (`payne_17` was used here) and **a
full backup first**, `persist` included. The TWRP README explains why that is not
boilerplate.

1. **Coming from the stock Android 7 or from LineageOS 16, format data** in TWRP
   (*Wipe → Format Data*). This erases everything on internal storage. Going from 16
   to 20 keeping the data has not been tried: 20 is signed with other keys, and Android
   refuses system apps signed by someone else unless that is migrated first.
2. Install the zip from TWRP. It writes `system` and `boot` only; the recovery stays,
   and the `boot` image is already signed for this bootloader.
3. If you want the Google apps, install them now, before the first boot (below).
4. Reboot. The first boot takes a few minutes.

Updating from one build to the next is step 2 alone, without a wipe. Leave `/data`
mounted in TWRP while installing, as it is by default: the script that carries the
Google apps across an update keeps its temporary files there, and without it they are
lost.

The image is a `userdebug` build signed with its author's own keys, not with AOSP's
public test keys. adb is off until you switch it on in the developer options, and asks
before trusting a computer.

## Google apps

None are in the image. The package checked here is
[MindTheGapps 13.0.0 for arm64](https://github.com/MindTheGapps/13.0.0-arm64/releases)
(the build of 25 October 2023), the one LineageOS' wiki names for 20. Install its zip
from TWRP right after the ROM and before the first boot.

With it Google's setup wizard goes through, the Assistant opens on a long press of
*home*, and the Play Store offers apps at its first start and installs them. The Play
Store may say the device is not certified; Google's remedy is to register the tablet at
<https://www.google.com/android/uncertified/> with its Google Services Framework ID.
[README-LOS16.md](README-LOS16.md) shows how to read it; the ID is new after every
*Format Data*.

## Building

[BUILDING-LOS20.md](BUILDING-LOS20.md) has the steps, what the build host needs, and
every problem met on the way with what was done about it. Signing with keys of your own
works as described for 16 in [README-LOS16.md](README-LOS16.md), with the additions
listed in BUILDING-LOS20.md.

Nothing proprietary is committed here: not the blobs, which are not ours to
redistribute, and not ASUS' init scripts, which are theirs. Both come off your own
tablet.

## Credits

[LineageOS](https://lineageos.org/), and [LineageOS-UL](https://github.com/LineageOS-UL),
whose forks are what let Android 13 run on a 3.10 kernel at all. The Galaxy Tab S2 and
Sony Kitakami trees of LineageOS 20, with SoCs of the same years, were the reference for
some of the fixes. Kernel sources published by ASUS.
