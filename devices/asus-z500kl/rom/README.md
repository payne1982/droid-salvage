# LineageOS 16.0 for ASUS_P00I — work in progress

This does not boot yet. It is the device tree being built up towards M3 in
[../ROADMAP.md](../ROADMAP.md): a boot that can be watched, rather than a usable tablet.

- **what the hardware is, and where each piece comes from:** [HARDWARE.md](HARDWARE.md)
- **the kernel:** [../kernel/](../kernel/) — buildable from ASUS' sources, and built
  inside this tree
- **why Android 9 and not something newer:** [../ROADMAP.md](../ROADMAP.md)

## Setting it up

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

# 5. build
# WITH_ADB_INSECURE: during bring-up adb must work without being authorised on the
# screen, because the screen may well not work yet. LineageOS only allows that on eng
# builds or with this variable (vendor/lineage/config/common.mk). Drop it for a release.
cd <tree> && source build/envsetup.sh && lunch lineage_ASUS_P00I-userdebug && WITH_ADB_INSECURE=true mka bacon
```

Step 4 takes partition dumps rather than a device on purpose. It needs no root and no
mounting — `debugfs` reads an ext4 image directly — it is reproducible, and it works
when the tablet does not boot, which is when you are most likely to want it. There is a
`--from-device` mode for a running tablet if you prefer.

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

## State of each piece

| piece | state |
|---|---|
| `BoardConfig.mk` | written; the open questions are listed at the end of it rather than guessed |
| `device.mk` | graphics, keymaster, gatekeeper, light, power, health. The rest is listed, not guessed |
| `rootdir/etc/fstab.qcom` | ours, rewritten from stock: no `verify`, no `rebooterr` |
| `proprietary-files.txt` | 72 files for M3, in four documented blocks |
| `tools/extract-files.sh` | works, 72 of 72 from the dumps |
| ASUS' init scripts | extracted, **not yet adapted** — they are written for Nougat's init and Pie's is stricter |
| `lunch` | passes: `LINEAGE_VERSION=16.0-…-ASUS_P00I`, arm64 with a 32-bit second arch |
| `mka bootimage` | the kernel builds inside the tree; the rest is in progress |
