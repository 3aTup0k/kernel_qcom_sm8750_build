# kernel_qcom_sm8750_build

GitHub Actions build of the **Xiaomi 15 (dada, SM8750) GKI kernel** — custom
"MaybeKernel" flavour.

The kernel source lives in the fork
[`3aTup0k/android_kernel_qcom_sm8750`](https://github.com/3aTup0k/android_kernel_qcom_sm8750)
(branch `lineage-23.2`). This repository only contains the CI that builds it,
so the kernel repo stays clean.

## How to run

- **Actions → Build kernel → Run workflow** (manual), or
- it runs automatically on every push and once a week (Saturday 03:00 UTC).

The `kernel_ref` input selects which kernel branch/tag to build (default
`lineage-23.2`).

## What it produces

An artifact named `Image-<ref>-<run number>` containing:

| file | contents |
|------|----------|
| `Image` | the ARM64 kernel image |
| `kernel.config` | the effective `.config` used |
| `README.txt` | the exact `Linux version ...` string and the source commit |

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

## Notes

- Build time on a standard 4-core runner is roughly **1–3 hours**.
- The kernel is built **with the config committed in the kernel repo**
  (`arch/arm64/configs/gki_defconfig`), including the SELinux permissive
  default. Nothing else is patched here.
