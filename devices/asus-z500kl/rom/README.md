# LineageOS 16.0 for ASUS_P00I

Android 9 on the ZenPad 3S 10 LTE, from a device tree written for it, a kernel built from
ASUS' sources and the Nougat vendor blobs taken off your own tablet. It runs as a daily
tablet with SELinux enforcing, and no image has been published yet: the last checks
before a first release are listed below.

- **what the hardware is, and where each piece comes from:** [HARDWARE.md](HARDWARE.md)
- **the kernel:** [../kernel/](../kernel/) — buildable from ASUS' sources, and built
  inside this tree
- **why Android 9 and not something newer:** [../ROADMAP.md](../ROADMAP.md)
- **what it took, problem by problem:** [NOTES.md](NOTES.md)

## What works

Every item below has been checked on the tablet, on a release build with SELinux
enforcing.

| | |
|---|---|
| display, touch, buttons, the magnetic cover | yes |
| audio: speaker, internal microphone, headset and its microphone | yes |
| Wi-Fi, 5 GHz included, with the tablet's own MAC address | yes |
| Bluetooth, with audio | yes |
| sensors: accelerometer, gyroscope, compass, light, hall | yes, 25 hardware sensors |
| hardware video decoding: H.264, HEVC (up to 4K), MPEG-4, VP8, VP9 | yes |
| hardware video encoding (camera recording, screen recording) | yes |
| cameras, rear and front: photos and video | yes — video records at about 11 fps, under investigation |
| GPS | yes |
| modem: comes up, reads the IMEI | yes — **calls and mobile data not yet tested with a SIM** |
| USB: charging, adb with on-screen authorisation, file transfer (MTP) to a Windows PC | yes |
| removable storage: FAT32, exFAT (files over 4 GB included), NTFS | yes — exFAT and NTFS checked with disk images given to Android as a card, not yet with a card in the slot |
| CPU frequency scaling and low-power states as on stock | yes |
| standby | yes — one night with Wi-Fi connected: 94% of it in deep sleep, about 1% of the battery in 8 h 40. Wi-Fi still wakes the tablet every 12 s to restart a scan, under investigation |

Not there:

- **Widevine.** The only DRM plugin installed is ClearKey, so the streaming apps that
  require Widevine (Netflix, Prime Video, Disney+ and the like) will not play. Whether
  the Nougat Widevine blobs can be made to work under Pie has not been tried.
- **Qualcomm's network location and geofencing** (IZat). GPS works without them.
- **Battery usage figures in Settings.** The level is right. The per-app estimates and
  the discharge in mAh are not: the tree has no power profile yet, so Android assumes a
  1000 mAh battery where this one is 7800, and the charge counter reads zero.

Not tested yet — none of these is known to be broken, and none is known to work:

- **calls, SMS and mobile data.** The modem comes up and reads the IMEI; no SIM has
  been in the tablet.
- **the other USB modes** in the notification: PTP, MIDI, tethering. File transfer,
  the default, works.
- **a card in the slot formatted exFAT or NTFS.** Both mount from a disk image.
- **encrypting `/data`.** LineageOS runs here on an unencrypted `/data`. The partition
  table allows encryption (`encryptable=footer`, the hardware-backed kind stock used),
  but it has never been switched on under Pie. Do not switch it on to find out on a
  tablet with data you care about: if it fails, the way back is *Format Data*.
- **Wi-Fi hotspot and USB tethering.**
- **USB OTG**: sticks, keyboards, mice.
- **charging with the tablet switched off.**
- **screen casting** (Miracast).

## Installing

You need the [TWRP for this tablet](../README.md), and **a full backup first** —
including the last 16 KB of `userdata`, the encryption footer, which no other backup
covers and which cannot be recreated. The TWRP README explains why that is not
boilerplate.

1. **Coming from the stock Android 7, format data** in TWRP (*Wipe → Format Data*). This
   erases everything on internal storage. Nothing on stock's encrypted `/data` is
   carried over, and LineageOS starts on an unencrypted one.
2. Install the zip from TWRP. It writes `system` and `boot` only; the recovery stays.
3. Reboot. The first boot takes a few minutes.

The `boot` image inside the zip is already signed for this bootloader (AVB1, AOSP test
key), so nothing has to be written by hand afterwards. Expect the usual warning screens
at boot; see the TWRP README for why they are harmless.

Updating from one build to the next is step 2 alone: no wipe.

## Building

```sh
# 1. the LineageOS 16.0 manifest
repo init -u https://github.com/LineageOS/android.git -b lineage-16.0 --depth=1
repo sync -c -j4 --no-clone-bundle

# 1b. WebView is stored in Git LFS, and repo leaves only a 134-byte pointer where the
#     243 MB APK should be. The build gets ~94% of the way and then fails packaging it
#     with "java.util.zip.ZipException: zip END header not found". Each architecture is
#     its own project; arm64 carries the 32-bit half too, so it is the only one needed.
#     --local because repo configured that repository to skip LFS.
( cd external/chromium-webview/prebuilt/arm64 && git lfs install --local && git lfs pull )

# 2. this device tree
rsync -a devices/asus-z500kl/rom/device/ <tree>/device/

# 3. the kernel, with the patches that make it configurable at all
devices/asus-z500kl/kernel/tools/setup-kernel.sh      # KERNEL_TREE=<tree>/kernel/asus/msm8956

# 4. the vendor blobs and ASUS' init scripts
cd <tree>/device/asus/ASUS_P00I
./tools/extract-files.sh --from-dumps /path/to/system.img /path/to/boot.img

# 4b. the GPS HAL source, fetched at a pinned commit (the script says why)
./tools/setup-gps.sh

# 5. build
cd <tree> && source build/envsetup.sh && lunch lineage_ASUS_P00I-userdebug
device/asus/ASUS_P00I/tools/release-build.sh payne_N     # a release
WITH_ADB_INSECURE=true mka bacon                         # or a development build
```

**Release or development build.** A release has secure adb: off until it is switched on
in developer options, and then only for a computer whose key has been accepted on the
screen. `release-build.sh` also gives the build its own fingerprint, and checks both
things in the result. A development build turns adb on without authorisation, which is
what bring-up needs when the screen cannot be trusted yet — and what a tablet in daily
use should not have.

Step 4 takes partition dumps rather than a device on purpose. It needs no root and no
mounting — `debugfs` reads an ext4 image directly — it is reproducible, and it works
when the tablet does not boot, which is when you are most likely to want it. There is a
`--from-device` mode for a running tablet if you prefer.

A few of the Nougat blobs need a few bytes patched to work under Pie (the camera HAL and
ISP library). `extract-files.sh` does it, and only to a file whose SHA-256 and original
bytes are exactly the expected ones; the comments there say what each patch does and
why.

Nothing proprietary is committed here: not the blobs, which are not ours to
redistribute, and not ASUS' init scripts, which are theirs. Both come off your own
tablet. What is committed is what we wrote and the reasoning behind it.

## Where GitHub's rate limit will bite

`repo sync` of a tree this size will hit GitHub's limit on unauthenticated git
downloads partway through, with a misleading error — `repo` reports *"git requires
authentication"*, which sends you looking at your credentials. The real message is in
the HTTP exchange:

```
x-github-edge-message: GitHub is temporarily limiting some unauthenticated downloads
                       to protect the stability of the platform.
                       Please retry later or authenticate.
```

Retrying at `-j2` with pauses gets most of the way; authenticating finishes it. SSH
works because it is authenticated by definition, so a temporary key plus
`url."git@github.com:".insteadOf "https://github.com/"` is the least invasive route —
it leaves the manifest and the recorded remotes untouched.

## Before a first release

From the lists above, the ones a first image should not go out without:

- calls, SMS and mobile data with a SIM;
- an exFAT card in the slot;
- the camera's video frame rate.
