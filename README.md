# kernel_qcom_sm8750_build

GitHub Actions build of the **Xiaomi 15 (dada, SM8750) GKI kernel** — custom
"MaybeKernel" flavour — packaged as a flashable **AnyKernel3** installer and
published to GitHub releases.

The kernel source lives in the fork
[`3aTup0k/android_kernel_qcom_sm8750`](https://github.com/3aTup0k/android_kernel_qcom_sm8750)
(branch `lineage-23.2`). This repository only contains the CI and the
AnyKernel3 template, so the kernel repo stays clean.

## How to run

- **Actions → Build kernel → Run workflow** (manual) — builds and **publishes a
  release**; or
- it runs automatically on every push and once a week (Saturday 03:00 UTC) —
  those runs only upload a build artifact, no release.

Manual inputs:

| input | default | meaning |
|-------|---------|---------|
| `kernel_ref` | `lineage-23.2` | kernel branch/tag to build |
| `kernel_release` | `R1.2` | release version used in the installer name and the release tag |
| `update_ksu` | `no` | re-vendor the latest upstream KernelSU before building (see [KernelSU](#kernelsu)) |

## What it produces

**Installer file name**

```
<ROOT_MANAGER>-<codename>-<PLATFORM>-<KERNEL_NAME>_<release>-kernelsu_<KSUVER>.zip
```

e.g. `KernelSU-dada-SM8750-MaybeKernel_R1.2-kernelsu_32680.zip`

`KSUVER` is read from `drivers/kernelsu/Kbuild` (`KSU_VERSION ?= 32680`).

**Release tag**: `<release>-<short kernel commit hash>`, e.g. `R1.2-274331381405`.
With `update_ksu = yes` the tag also carries the KernelSU version, e.g.
`R1.2-274331381405-ksu32682`, because that build is not a committed revision.

Every run also uploads the same zip as a workflow artifact (kept 30 days).

## How it builds

The build uses the plain `make` + clang method (the same one the upstream
author documents for this tree) — **no `repo`, no kleaf**, so a normal GitHub
runner is enough:

1. free disk space and add swap (the final LTO link is memory-hungry);
2. check out the kernel fork;
3. download the AOSP `clang-r510928` toolchain (cached between runs);
4. `make O=out gki_defconfig && make -j$(nproc) O=out Image`.

Because clang is loaded with `LLVM=1 LLVM_IAS=1`, gcc is not required.

### Version string

A plain `make` build would normally report `6.6.144-4k-MaybeKernel`, while a
kleaf build reports `6.6.144-android15-8-4k-MaybeKernel-<hash>`. To keep the CI
output identical to a kleaf build, the workflow writes a `localversion` file
containing `-android15-8-g<hash>` before building, so the resulting string is:

```
6.6.144-android15-8-4k-MaybeKernel-g<hash>
```

## AnyKernel3 template

The installer template lives in [`anykernel/`](anykernel): `anykernel.sh`,
`banner`, `META-INF/`, `tools/` (busybox, magiskboot, …). The CI drops the
freshly built `Image` in and zips the whole directory.

- `do.modules=0` — boot only, it patches the boot ramdisk (GKI); vendor modules
  are left untouched.
- To change the on-device string or banner, edit
  [`anykernel/anykernel.sh`](anykernel/anykernel.sh) / `anykernel/banner`.

## KernelSU

The kernel tree vendors upstream [`tiann/KernelSU`](https://github.com/tiann/KernelSU)
in `drivers/kernelsu`, with SUSFS grafted in from `simonpunk/susfs4ksu` — the
full story is in `apex-patches/kernelsu/README.md` in the kernel repo. `KSUVER`
in the installer name is read from `KSU_VERSION ?= <30000 + upstream commit
count>` in `drivers/kernelsu/Kbuild`.

There are two ways to pick up a newer KernelSU:

1. **Update the kernel repo (preferred).** The kernel fork carries a weekly
   `Sync KernelSU` workflow that re-vendors the latest upstream and opens a pull
   request (`ksu-sync/<version>`) for review. Merging that request into
   `lineage-23.2` puts the new KernelSU into the tree, and every later build
   picks it up.
2. **At build time.** Run this workflow with `update_ksu = yes`. It applies the
   same sync inside the runner **without committing anything**, so the build
   uses the latest KernelSU but the result is not a reproducible revision —
   hence the extra `-ksu<version>` in the release tag.

Both paths use [`scripts/sync-kernelsu.sh`](scripts/sync-kernelsu.sh), which
re-vendors `drivers/kernelsu` + `drivers/uapi`, re-applies
`10_enable_susfs_for_ksu.patch`, and redoes the local fixes (drop the two
`if (fn)` guards in `feature/selinux_hide.c`, pin `KSU_VERSION` in `Kbuild`,
refresh the revision note in `apex-patches/kernelsu/README.md`).

The SUSFS patch is written against a specific KernelSU revision. Once upstream
has moved far enough that it no longer applies, the sync **fails** — it never
commits a half-broken tree — and the patch has to be refreshed.

## Notes

- Build time on a standard 4-core runner is roughly **20–40 minutes**.
- The kernel is built **with the config committed in the kernel repo**
  (`arch/arm64/configs/gki_defconfig`), including the SELinux permissive
  default. Nothing else is patched here.
