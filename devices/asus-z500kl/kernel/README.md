# Kernel for ASUS_P00I — buildable from source

ASUS published the kernel sources for this tablet
([mirror](https://github.com/6ccg/android_kernel_asus_z500kl)), and for years that
looked like a dead end: a fresh checkout cannot even be configured.

This directory is the fix. Two files and two scripts, and the tree builds.

## Why a plain checkout cannot be configured

`arch/arm64/configs` holds defconfigs for msm8994 and two generic `msm` targets.
There is **none** for the MSM8956 family this tablet uses. That is not an oversight:
ASUS replaced the upstream `%_defconfig` rule in `scripts/kconfig/Makefile` with one
of their own.

```make
%_defconfig: $(obj)/conf
	@echo " Make kernel configs with diffconfig ++"
	cat $(ANDROID_BUILD_TOP)/kernel/arch/$(SRCARCH)/configs/$@ \
	    $(ANDROID_BUILD_TOP)/vendor/asus/bsp/${TARGET_PROJECT}/${TARGET_PROJECT}_diffconfig \
	    > $(OUT)/merge_config.tmp
	$(Q)$< --defconfig=$(OUT)/merge_config.tmp $(Kconfig)
```

Every configuration target goes through a per-project `_diffconfig` under
`vendor/asus/bsp/`. Nothing under `vendor/asus` was ever published, so the file does
not exist, and `make <anything>_defconfig` dies with

```
/bin/sh: 1: cannot create /merge_config.tmp: Permission denied
```

So the published sources are real sources, but the configuration that turns them
into *this tablet's* kernel was kept back.

## Where the configuration came from instead

The shipped kernel is built with `CONFIG_IKCONFIG=y`, which embeds the kernel's own
configuration into the image as a gzip blob between the markers `IKCFG_ST` and
`IKCFG_ED`. `CONFIG_IKCONFIG_PROC` is *not* set, so there is no `/proc/config.gz` to
read on the device — the configuration has to be taken out of the kernel binary, which
is what the kernel's own script does:

```sh
# the kernel out of the stock boot image, decompressed to arch/arm64/boot/Image form
scripts/extract-ikconfig Image.stock > Z500KL_running.config   # 4134 lines, 1307 options
```

That is the real thing — not a reconstruction, the configuration the shipped kernel
was compiled with. Fed back into the published tree it checks out exactly:

```
$ make ARCH=arm64 listnewconfig
(nothing)
```

Zero new symbols: the published sources cover the shipped kernel's configuration
space with nothing missing and nothing left over. `savedefconfig` then reduces it to
the 607 lines of `asus_P00I_defconfig`, and that round-trips back to the full
configuration byte for byte.

With a complete defconfig in hand the missing `_diffconfig` has nothing left to
contribute, so `patches/0001-*` simply restores the upstream rule.

## Building

```sh
tools/setup-kernel.sh      # clone, apply patches, install the defconfig
tools/build-kernel.sh      # -> out/arch/arm64/boot/Image.gz-dtb
```

Set `KERNEL_TREE` and `KERNEL_TOOLCHAIN` in `local.conf` first. Two traps, both
handled by the script but worth knowing:

- **`TARGET_PROJECT=Z500KL` is mandatory.** The DTS Makefile builds
  `msm8956-v1.1-cdp-$(TARGET_PROJECT).dtb`. Without it the tablet's own device tree
  is never compiled, and a kernel with no matching DTB does not boot.
- **`CC` has to be overridden.** The top-level Makefile routes every compiler
  invocation through `scripts/gcc-wrapper.py`, which is Python 2. Pointing `CC`
  straight at gcc skips it; all it does is promote some warnings to errors.

The toolchain is the AOSP prebuilt `aarch64-linux-android-4.9`. A current gcc will
not compile a 3.10 kernel, and those prebuilts are x86_64-only, so the build needs an
x86_64 host — the same one used for TWRP.

`CONFIG_BUILD_ARM64_APPENDED_DTB_IMAGE_NAMES` is left empty, as in the stock
configuration, so all 100 DTBs are appended to `Image.gz` and the bootloader picks
the matching one by `qcom,msm-id`/`qcom,board-id`. For this tablet (MSM8956 **rev
1.1**) that is `msm8956-v1.1-cdp-Z500KL.dtb`.

### Gotcha on a modern distribution

The host tools (`scripts/dtc`, `scripts/mod`, ...) are compiled with the *system* gcc,
and a 2015 tree does not survive a 2026 one untouched. Since gcc 10 the default is
`-fno-common`, while `scripts/dtc` declares `yylloc` in both the lexer and the parser:

```
/usr/bin/ld: scripts/dtc/dtc-parser.tab.o:(.bss+0x50): multiple definition of `yylloc'
```

`build-kernel.sh` adds `-fcommon` to `HOSTCFLAGS`, which fixes that whole class of
breakage without patching anything. Note this is the *host* compiler only; the kernel
itself is built by gcc 4.9, which predates the change.

## It reproduces ASUS's own output

The compiled kernel cannot be byte-identical to the shipped one — different compiler
build, different timestamps, and `CONFIG_LOCALVERSION_AUTO` stamps in the git hash.
The device tree blob, however, can be, and is:

```
0bc816c660d6572255460a78d00f636f162a7bdd045f6e24d7d90be29f689864  our msm8956-v1.1-cdp-Z500KL.dtb
0bc816c660d6572255460a78d00f636f162a7bdd045f6e24d7d90be29f689864  DTB #80 pulled out of the stock boot image
```

Same sha256. That settles three things at once: the published sources really are the
ones the shipped kernel was built from, `TARGET_PROJECT=Z500KL` is the right value,
and the DTB this tablet runs is the one we now build.

The configuration travels inside the image, so it can be compared the same way, and
it matches as well:

```sh
scripts/extract-ikconfig <our Image>      # 4134 lines
scripts/extract-ikconfig <stock Image>    # 4134 lines, identical
```

The kernel image lands in the same place too — `Image` is 20 047 744 bytes against the
stock 20 048 024, a difference of 280 bytes — and the build appends 100 DTBs, exactly
as the stock boot image does.

### Confirmed on the tablet

`payne_14`, a TWRP image identical to the released `payne_13` except for this kernel,
boots and runs:

```
Linux version 3.10.84-perf-g68a4f29d-dirty (payne@payne-hp450)
  (gcc version 4.9.x 20150123 (prerelease) (GCC)) #1 SMP PREEMPT
```

against the stock kernel's `3.10.84-perf-g3eaf16a77f6-00007-g55252291255
(android@mec7)`. The `-dirty` comes from the kconfig patch and is a useful marker: it
tells the two apart at a glance in `/proc/version`. Touch probes and registers, the
partitions mount, `/data` decrypts, `adb` works, and `dmesg` holds no new failures.

`tools/patch-kernel.py` from the recovery tree found the `mxt_probe` guard in this
build too, at `0x5b7ee8` where the stock had it at `0x5b7b18` — the same instruction
at a different address. Locating it by scanning for code rather than at a fixed offset
turned out to be worth the trouble.

For the record: 7 minutes 21 seconds on two cores of an i5-7200U, 0 errors, 20
warnings, all of them from the host tools.

## What changed on top of ASUS's configuration

The patches and six configuration options below. All of it is in `patches/` and
`asus_P00I_defconfig`, and all of it is confirmed running on the tablet.

`patches/0002` moves the touchscreen fix out of the compiled image and into the driver,
and makes it narrower while it is there. `patches/0003` fixes a genuine bug in the tree:
`mm/memcontrol.c` defines `mem_cgroup_allow_attach()` three times, so `CONFIG_MEMCG`
does not compile at all. Nobody had hit it because no ASUS configuration for this board
turns MEMCG on, which means that file had never been built.

`patches/0004` gives the kernel what Android 8 and later need from binder: three
devices instead of one, and the scatter-gather and file-descriptor-array transactions
that HIDL sends over `/dev/hwbinder`. It is LineageOS' own backport for the Xiaomi
Redmi Note 3 Pro (kenzo), which has the same SoC and the same Qualcomm CAF 3.10 base:
fourteen commits replayed in order on the ASUS files, with no conflicts, giving kenzo's
files exactly. The patch header lists them and explains why this source and not
Google's `deprecated/android-3.10` branch.

The first version of this patch stopped at the three devices, and that looked like
enough until LineageOS actually booted: every HIDL service failed to register, healthd
crashed four times and init sent the tablet to the bootloader. Having `/dev/hwbinder`
is not the same as speaking its protocol. The devices part, confirmed on the tablet:

```
$ ls /dev/*binder*
/dev/binder  /dev/hwbinder  /dev/vndbinder
$ grep -i binder /proc/misc
 56 vndbinder
 57 hwbinder
 58 binder
```

Verification, with `CONFIG_IKCONFIG_PROC` now in place so the device can be asked
directly:

```
$ adb exec-out cat /proc/config.gz | gunzip - | diff - <(scripts/extract-ikconfig out/.../Image)
(nothing)
$ adb shell cat /proc/cgroups
#subsys_name	hierarchy	num_cgroups	enabled
cpuset	0	1	1
cpu	0	1	1
cpuacct	1	9	1
memory	0	1	1
freezer	0	1	1
```

`cpuset` and `memory` were absent before. Touch, mounts, `/data` decryption and `adb`
all still work, and `dmesg` has nothing new in it.

`patches/0005` and `patches/0006` are build fixes for LineageOS (`O_TMPFILE` in the uapi
headers; `__BITS_PER_LONG` keyed on `__LP64__`, because the arm64 kernel headers reach
32-bit HALs too). Their headers explain both.

`patches/0007` adds sdcardfs, with the VFS hooks it needs (`d_canonical_path`, private
mount data, `permission2`/`setattr2`/`truncate2`, remount propagation). Pie's `sdcard`
daemon has no FUSE path left: without sdcardfs it aborts, and apps get no `/sdcard` at
all. Same source as 0004, LineageOS' kenzo kernel, where sdcardfs begins with "port to
3.10"; 89 commits replayed with no conflicts, and the result matches kenzo's in
`fs/sdcardfs/`, `magic.h`, `mount.h` and `pnode.[ch]`. The defconfig sets
`CONFIG_SDCARD_FS=y`. `patches/0008` is ours: it fixes a double free in the private mount data
that kenzo's port carries and Pie's sdcard daemon triggers (its first mount attempts fail
by design); without it the first sdcardfs boot crash-looped. The patch header has the
whole trail, from the oops to the two numbers in it that were the mount options.

`patches/0009` and the prima fetch in `tools/setup-kernel.sh` add the WiFi driver.
ASUS built `wlan.ko` out of tree from sources they did not publish, and their module
does not load on a kernel we build. This is Qualcomm's prima for the WCNSS Pronto core
as LineageOS carries it in the kenzo kernel (CAF `LA.BR.1.3.6_rb1.19`), built in. It is
28 MB, so it is fetched at a pinned commit instead of living in a patch; 0009 is the
two lines that wire it into `drivers/staging`. The defconfig gains kenzo's eight prima
options (`PRONTO_WLAN`, roaming, OKC, 11ac, 11w, 11r, Linux regulatory, TDLS -- the
driver does not compile without TDLS).

`patches/0010` is ambient capabilities (Linux 4.3), as kenzo backported them. Pie's
init grants a service its declared capabilities that way; without them it starts the
service with none. The WiFi HAL needs `NET_ADMIN` to bring `wlan0` up, so WiFi could
not be switched on although the driver and the radio worked.

`patches/0011` is a CAF commit to the video driver (`msm_vidc`) that kenzo carries:
the I-frame size hint, a V4L2 control the Venus encoder in `media-caf/msm8952` sets
and the ASUS headers do not define, so the encoder did not compile. It brings the
control and its handling in the driver together, rather than a definition the
driver would then reject.

## A note for anyone building the recovery

With the kernel built from these sources, `tools/patch-kernel.py` in the TWRP device
tree is no longer needed: the digitiser fix is `patches/0002`. That script stays for the
other route, where you take the stock kernel off your own tablet and patch the binary.

Building the kernel is the better route, and not only for tidiness: it removes the
kernel from the list of things you need a working tablet to obtain. What still has to
come off the device is the vendor firmware and the Nougat `property_contexts`.

## What the stock configuration lacks for a newer Android

Checked against the running configuration. All five are additive, so a kernel with
them still boots the stock Android 7:

| option | why |
|---|---|
| `CONFIG_CPUSETS` | Android 8+ init mounts `/dev/cpuset` and writes task profiles into it |
| `CONFIG_MEMCG` | used by `lmkd` from Android 8 on |
| `CONFIG_FHANDLE` | expected by an Android 8+ userspace |
| `CONFIG_TMPFS_POSIX_ACL` | expected by a modern userspace |
| `CONFIG_SECURITY_SELINUX_BOOTPARAM` | adds a `selinux=0` kernel parameter, an escape hatch for bring-up if a policy turns out to be unloadable |
| `CONFIG_IKCONFIG_PROC` | makes `/proc/config.gz` exist, so the running kernel's configuration can be checked on the device instead of only in the image |

A note on SELinux, because it is easy to get backwards: **permissive mode needs no
kernel change here.** `CONFIG_SECURITY_SELINUX_DEVELOP=y` is already set in the stock
configuration, and that is the option that allows permissive mode and toggling through
`/sys/fs/selinux/enforce`. `androidboot.selinux=permissive` is read by Android's `init`
in userspace, not by the kernel. `CONFIG_SECURITY_SELINUX_BOOTPARAM` is a different and
blunter thing — `selinux=0` keeps the LSM from registering at all — which is worth
having for bring-up but is not what makes permissive possible.

These are enabled because an Android 8+ userspace exercises them, they are additive,
and they cost little: `MEMCG_KMEM` and `MEMCG_SWAP`, the expensive parts, stay off. The
honest caveat is that AOSP's `android-base.config` requirements target kernels 4.4 and
newer, so there is no authoritative list for a 3.10, and the real verification is M3,
where `init` says out loud what it cannot find.

And two that are not in this kernel at all, which is what sets the ceiling:

- **no `fs/sdcardfs`.** Android 9 still ships the FUSE `sdcard` daemon as a fallback,
  so Pie works without it (more slowly). Android 10 removed that daemon.
- **no `bpf()` syscall.** It arrived in Linux 3.18. Android 10's `netd` requires eBPF
  for traffic accounting.

That is the honest reason the first ROM target here is Android 9 and not something
newer: on 3.10 the wall is not the bootloader, it is `bpf()`.
