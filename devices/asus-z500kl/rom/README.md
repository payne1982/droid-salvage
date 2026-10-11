# LineageOS 16.0 for ASUS_P00I

Android 9 on the ZenPad 3S 10 LTE, from a device tree written for it, a kernel built from
ASUS' sources and the Nougat vendor blobs taken off your own tablet. It runs as a daily
tablet with SELinux enforcing. The first image, `payne_31`, is on the
[Releases](https://github.com/payne1982/droid-salvage/releases) page; what it does not
do, and what nobody has tried on it yet, is listed below.

- **what the hardware is, and where each piece comes from:** [HARDWARE.md](HARDWARE.md)
- **the kernel:** [../kernel/](../kernel/) — buildable from ASUS' sources, and built
  inside this tree
- **why Android 9 first:** [../ROADMAP-LOS16.md](../ROADMAP-LOS16.md); **what comes after:** [../ROADMAP.md](../ROADMAP.md)
- **what it took, problem by problem:** [NOTES.md](NOTES.md)

## What works

Every item below has been checked on the tablet, on a release build with SELinux
enforcing. The whole round was then repeated on a clean installation of the same image
-- *Format Data*, install, first boot -- except for the SIM and the card in the slot,
which were checked on the installation before it.

| | |
|---|---|
| display, touch, buttons, the magnetic cover | yes |
| audio: speaker, internal microphone, headset and its microphone | yes |
| Wi-Fi, 5 GHz included, with the tablet's own MAC address | yes — while the tablet sleeps the connection drops now and then; the chip finds the network again by itself within seconds. Why it drops is under investigation |
| Bluetooth, with audio | yes |
| sensors: accelerometer, gyroscope, compass, light, hall | yes, 25 hardware sensors |
| hardware video decoding: H.264, HEVC (up to 4K), MPEG-4, VP8, VP9 | yes |
| hardware video encoding (camera recording, screen recording) | yes |
| DRM: Widevine (level 3) and ClearKey | yes — checked by provisioning and opening a session, not yet with a streaming app |
| cameras, rear and front: photos and video | yes — 1080p video at 30 fps in good light. In a dim room the camera stretches the exposure to 1/12 s and video drops to 11.5 fps, although the app asks for a steady 30 |
| GPS | yes |
| mobile network with a SIM: data on LTE and 3G, SMS in both directions | yes — the APN was picked from the SIM without help. **No voice calls**, see below. |
| USB: charging, adb with on-screen authorisation, file transfer (MTP) to a Windows PC | yes — behind one external USB hub, booting with the cable in, the port was taken for a charger and the computer did not see the tablet until the cable was plugged again; on a direct port it does not happen |
| removable storage: FAT32, exFAT (files over 4 GB included), NTFS | yes — exFAT with a card in the slot, and with a disk image given to Android as a card for the files over 4 GB; NTFS with a disk image only. A second partition Android cannot mount gets its own *Issue with SD card* notification, which leads to formatting it: leave it alone. That is what an ext4 partition made by a current Linux gets, since this kernel cannot load its journal: it is checked, found clean, and the mount is refused |
| CPU frequency scaling and low-power states as on stock | yes |
| standby | yes — one night with Wi-Fi on: 94% of it in deep sleep, about 1% of the battery in 8 h 40, measured before the Wi-Fi scan fix that should lower it further |

Not there:

- **Widevine level 1.** Widevine itself works, with the tablet's own plugin: Google's
  server provisions it and sessions open. But it runs at level 3, the software one,
  which streaming services usually limit to standard definition. Level 1 needs the
  Widevine trustlet in the TrustZone, and the TrustZone refuses to load it, from this
  system and from the recovery alike. Stock Android loaded the same file on the same
  tablet, and what the kernel is told about the hardware is identical, byte for byte;
  the hardware keymaster, which the bootloader loads, works here too. What is left is
  the boot image: ours is not signed by ASUS, the bootloader reports that to the
  TrustZone, and DRM trustlets are what that report exists to stop. Not proven -- the
  TrustZone's own log is switched off on this tablet -- and not something a ROM can fix.
- **Voice calls.** The network registers the tablet for voice, but the modem itself
  turns calls down: a dial request comes back as an invalid argument within 30 ms,
  before anything is sent to the network, on 3G and on LTE alike, and an incoming call
  never reaches Android while the caller hears busy. ASUS sold this tablet without a
  phone function and stock had no dialer; the ROM follows, with no Phone app. That
  includes emergency numbers: do not count on this tablet to call one.
- **Qualcomm's network location and geofencing** (IZat). GPS works without them.

Not tested yet — none of these is known to be broken, and none is known to work:

- **MMS.**
- **the other USB modes** in the notification: PTP, MIDI, tethering. File transfer,
  the default, works.
- **a card in the slot formatted NTFS.** It mounts from a disk image.
- **encrypting `/data`.** LineageOS runs here on an unencrypted `/data`. The partition
  table allows encryption (`encryptable=footer`, the hardware-backed kind stock used),
  but it has never been switched on under Pie. Do not switch it on to find out on a
  tablet with data you care about: if it fails, the way back is *Format Data*.
- **Wi-Fi hotspot and USB tethering.**
- **USB OTG**: sticks, keyboards, mice.
- **charging with the tablet switched off.**
- **screen casting** (Miracast).

Not tried — not on the list of things to do; here so that nobody takes them for
impossible, or for done:

- **switching voice calls on in the modem.** The refusal looks like configuration and
  not like missing hardware: the audio configuration ASUS shipped has every voice-call
  route in it. If it is a setting, it lives in the modem's own storage, out of reach of
  a ROM: changing it means Qualcomm's diagnostic tools, on each tablet, writing to
  partitions that hold the IMEI. Nobody has looked for the setting, and call audio has
  never been heard on this hardware.

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

The published image is a `userdebug` build signed with its author's own keys, not with
AOSP's public test keys ("Signing", below, is how to do the same with yours). adb is
off until you switch it on, and asks before trusting a computer.

## Google apps

None are in the image. If you want them, the package checked here is
[MindTheGapps 9.0.0 for arm64](https://github.com/MindTheGapps/9.0.0-arm64/releases/latest)
(the build of 22 September 2023), the one LineageOS' wiki points to for 16.0. Install
its zip from TWRP **right after the ROM and before the first boot**; it stays through
later updates of the ROM.

With it the tablet boots, signs in, keeps Google's push connection and installs apps
from the Play Store. Two things do not go by themselves.

**The setup wizard stops at the Google Assistant.** After you sign in it says the
Assistant "is not available for this account", blames an administrator and offers only
*Change account*. The account is not the reason: the Google app in the package dates
from 2018, and the request it makes for that step fails. Take that app out before the
first boot, from TWRP's terminal or over adb while still in TWRP:

```sh
mount /system
rm -r /system/priv-app/Velvet
umount /system
```

The wizard then has no such step. Here it was done after getting stuck, booting into
TWRP again; the wizard completed on the next boot with the account it already had.
What goes with that app is the Google search bar and the Assistant, and the Assistant
could not be set up with it left in either. The Play Store has no newer Google app
for this tablet: it lists the app as not compatible with this version of Android, so
the one in the package is the one that stays.

**The Play Store says the device is not certified.** Google does not know this build
as a certified one. Signing in and installing apps worked all the same. Google's own remedy is to register the tablet at
<https://www.google.com/android/uncertified/> with its Google Services Framework ID,
which a root shell reads with:

```sh
adb root
adb shell 'sqlite3 /data/data/com.google.android.gsf/databases/gservices.db "select value from main where name = \"android_id\";"'
```

That ID lives in `/data`: it survives updates of the ROM and is new after *Format Data*.
Registered here, the Play Store went on saying "not certified" in the minutes that
followed. A build declaring the fingerprint of ASUS' last firmware, as many device trees
do for this, was tried and made no difference, so the fingerprint stays this build's own.

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

# 4c. the changes to LineageOS' own sources: one so far, in the lock screen. Each patch
#     in tools/tree-patches/ says what it fixes
./tools/apply-tree-patches.sh

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

**Signing.** Without anything else the build is signed with AOSP's test keys, which are
public: anyone can sign an app with the platform one and Android will hand it the
system's own permissions. LineageOS says so at every boot (*Trust: this build was signed
with public keys*). To sign with keys of your own, put them in
`<tree>/vendor/lineage-priv/keys/` — `releasekey`, `platform`, `shared`, `media` and
`testkey`, each as `.pk8` and `.x509.pem` — with a `keys.mk` next to them:

```make
PRODUCT_DEFAULT_DEV_CERTIFICATE := vendor/lineage-priv/keys/releasekey
```

LineageOS includes that file when it exists; nothing in this repository changes. The
build is then tagged `dev-keys`, in `ro.build.tags` and in the fingerprint, and Trust has
nothing to say. Three things to know first:

- `releasekey` has to be RSA 2048. It is also the key updates are checked against, and
  Android 9's tools accept no other size for that (`dumpkey`: *Modulus should be 2048
  bits long*). The other four can be 4096.
- The private keys must be PKCS#8. `development/tools/make_key` writes that; OpenSSL 3's
  `genpkey -outform DER` writes the older RSA format instead, and every APK then fails
  to sign with *unknown object in getInstance: ASN1Integer*. `openssl pkcs8 -topk8
  -nocrypt` converts a key without changing it.
- A system that has run with one set of keys does not take a build signed with
  another: Android remembers who signed the system apps, in `/data/system/packages.xml`.
  Either format data, or migrate that file from the recovery before the first boot of
  the new build. Each certificate is written out once in it, as the hex of its DER form
  (`openssl x509 -outform DER`), and four of them are the test keys': replace `testkey`
  with your `releasekey`, and `platform`, `shared` and `media` with their namesakes.
  That is all LineageOS' own key-migration script does. The tablet went from test keys
  to private ones this way, with its apps and data, and booted in 51 seconds.

Keys are per builder and belong outside any repository.

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

Retrying at `-j2` with pauses gets most of the way: here the projects still missing
went 104, 36, 24 over three rounds. `device/asus/ASUS_P00I/tools/sync-retry.sh`, run
from the top of the tree, does that until none is left, and counts what is actually on
disk rather than trusting repo's exit status (`--count` only counts). Authenticating
finishes it at once. SSH works because it is authenticated by definition, so a
temporary key plus `url."git@github.com:".insteadOf "https://github.com/"` is the least
invasive route — it leaves the manifest and the recorded remotes untouched.

The build host itself needs what any Android 9 tree needs on a current distribution:
Python 2.7 under that name, `libtinfo.so.5`, and a few rewritten `#!` lines. The
[TWRP README](../README.md) has the list and the commands; the same environment builds
both.

## Loose ends

Two things the first image went out with, known and not settled:

- a cable plugged in **while the tablet is booting**. Seen once: the tablet charged,
  the computer did not see it, and plugging the cable again did not help until a
  reboot with the cable already in. Done again on purpose, at the same point of the
  boot, it worked. Not explained;
- standby has not been measured on this image. The night in the table above is from
  an earlier build, before the Wi-Fi scan fix.
