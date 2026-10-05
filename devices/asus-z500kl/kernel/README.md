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

The shipped kernel is built with `CONFIG_IKCONFIG=y`, which means it carries its own
configuration inside it, readable on the running device:

```sh
zcat /proc/config.gz > Z500KL_running.config    # 4134 lines, 1307 options
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

## What the stock configuration lacks for a newer Android

Checked against the running configuration. All five are additive, so a kernel with
them still boots the stock Android 7:

| option | why |
|---|---|
| `CONFIG_SECURITY_SELINUX_BOOTPARAM` | the one that matters most: without it `androidboot.selinux=permissive` is ignored, and bringing up a ROM while enforcing is debugging blindfolded |
| `CONFIG_CPUSETS` | Android 8+ init mounts `/dev/cpuset` and writes task profiles into it |
| `CONFIG_MEMCG` | used by `lmkd` from Android 8 on |
| `CONFIG_FHANDLE` | required from Android 8 on |
| `CONFIG_TMPFS_POSIX_ACL` | expected by a modern userspace |

And two that are not in this kernel at all, which is what sets the ceiling:

- **no `fs/sdcardfs`.** Android 9 still ships the FUSE `sdcard` daemon as a fallback,
  so Pie works without it (more slowly). Android 10 removed that daemon.
- **no `bpf()` syscall.** It arrived in Linux 3.18. Android 10's `netd` requires eBPF
  for traffic accounting.

That is the honest reason the first ROM target here is Android 9 and not something
newer: on 3.10 the wall is not the bootloader, it is `bpf()`.
