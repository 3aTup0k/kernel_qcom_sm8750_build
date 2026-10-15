#!/usr/bin/env bash
#
# Re-vendor the latest upstream KernelSU into a kernel tree and re-graft the
# in-tree SUSFS support.
#
# This mirrors the procedure documented in apex-patches/kernelsu/README.md:
#
#   1. copy upstream KernelSU kernel/ -> drivers/kernelsu, uapi/*.h -> drivers/uapi/
#   2. apply 10_enable_susfs_for_ksu.patch (SUSFS wiring for the driver)
#   3. local fix: drop the two "if (fn)" guards in feature/selinux_hide.c
#   4. local fix: pin KSU_VERSION in Kbuild
#
# The kernel-side SUSFS integration (50_add_susfs_in_gki-android15-6.6.patch and
# the fs/exec.c tweak) lives outside drivers/kernelsu and is already applied, so
# it is left untouched.
#
# Usage:
#   scripts/sync-kernelsu.sh <kernel-tree> [ksu-ref]
#
# Environment:
#   KSU_REPO            upstream repository (default https://github.com/tiann/KernelSU)
#   KSU_SYNC_ENV_FILE   if set, write KSU_COMMIT / KSU_COMMITS / KSU_VERSION there
#
# Exit codes:
#   0   synced, the tree changed
#   3   already up to date, the tree did not change
#   1   failed (patch no longer applies / files moved) - nothing is trusted
#
set -euo pipefail

KERNEL_TREE="${1:?usage: sync-kernelsu.sh <kernel-tree> [ksu-ref]}"
KSU_REF="${2:-main}"
KSU_REPO="${KSU_REPO:-https://github.com/tiann/KernelSU}"

KERNEL_TREE="$(cd "$KERNEL_TREE" && pwd)"
PATCH_DIR="$KERNEL_TREE/apex-patches/kernelsu"
[ -d "$PATCH_DIR" ] || { echo "ERROR: $PATCH_DIR not found"; exit 1; }
for f in 10_enable_susfs_for_ksu.patch Kbuild.reference README.md; do
    [ -f "$PATCH_DIR/$f" ] || { echo "ERROR: missing $PATCH_DIR/$f"; exit 1; }
done

command -v patch  >/dev/null || { echo "ERROR: 'patch' not installed";  exit 1; }
command -v python3 >/dev/null || { echo "ERROR: 'python3' not installed"; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo ">> cloning $KSU_REPO @ $KSU_REF"
git clone -q --branch "$KSU_REF" "$KSU_REPO" "$TMP/ksu"
KSU_COMMIT="$(git -C "$TMP/ksu" rev-parse --short HEAD)"
KSU_COMMITS="$(git -C "$TMP/ksu" rev-list --count HEAD)"
KSU_VERSION=$((30000 + KSU_COMMITS))
echo "   $KSU_COMMIT ($KSU_COMMITS commits) -> KSU_VERSION $KSU_VERSION"

# Machine-readable summary for CI (optional).
if [ -n "${KSU_SYNC_ENV_FILE:-}" ]; then
    {
        echo "KSU_REPO=$KSU_REPO"
        echo "KSU_REF=$KSU_REF"
        echo "KSU_COMMIT=$KSU_COMMIT"
        echo "KSU_COMMITS=$KSU_COMMITS"
        echo "KSU_VERSION=$KSU_VERSION"
    } > "$KSU_SYNC_ENV_FILE"
fi

echo ">> re-vendoring drivers/kernelsu and drivers/uapi"
rm -rf "$KERNEL_TREE/drivers/kernelsu"
cp -r "$TMP/ksu/kernel" "$KERNEL_TREE/drivers/kernelsu"
mkdir -p "$KERNEL_TREE/drivers/uapi"
cp "$TMP"/ksu/uapi/*.h "$KERNEL_TREE/drivers/uapi/"

echo ">> applying SUSFS driver patch (10_enable_susfs_for_ksu.patch)"
sed -e 's|a/kernel/|a/drivers/kernelsu/|g' \
    -e 's|b/kernel/|b/drivers/kernelsu/|g' \
    "$PATCH_DIR/10_enable_susfs_for_ksu.patch" > "$TMP/10.patch"

if ! patch -p1 --no-backup-if-mismatch -d "$KERNEL_TREE" < "$TMP/10.patch" > "$TMP/patch.log" 2>&1; then
    echo "ERROR: the SUSFS driver patch no longer applies to upstream $KSU_REF."
    echo "       KernelSU moved past the revision the patch was written for:"
    echo "       refresh apex-patches/kernelsu/10_enable_susfs_for_ksu.patch."
    cat "$TMP/patch.log"
    exit 1
fi
if grep -q 'FAILED' "$TMP/patch.log"; then
    echo "ERROR: some hunks failed:"
    cat "$TMP/patch.log"
    exit 1
fi
if grep -qi 'fuzz' "$TMP/patch.log"; then
    echo "WARNING: patch applied with fuzz - please review the result:"
    grep -i 'fuzz' "$TMP/patch.log"
fi
echo "   ok"

echo ">> local fix #1: drop the 'if (fn)' guards in feature/selinux_hide.c"
python3 - "$KERNEL_TREE/drivers/kernelsu" <<'PY'
import pathlib, sys
d = pathlib.Path(sys.argv[1])
p = d / "feature/selinux_hide.c"
s = p.read_text()
orig = s

# Guard 1: security_dump_masked_av_fn is a real function after the SUSFS patch,
# so "if (fn)" is always true and clang rejects it with -Wpointer-bool-conversion.
a_old = ("    if (security_dump_masked_av_fn)\n"
         "        security_dump_masked_av_fn(")
a_new = "    security_dump_masked_av_fn("
if a_old in s:
    s = s.replace(a_old, a_new)
else:
    print("   note: guard #1 not present")

# Guard 2: the else branch calls the static context_struct_compute_av directly.
b_old = ("    if (context_struct_compute_av_fn) {\n"
         "        context_struct_compute_av_fn(policydb, scontext, tcontext, tclass, avd, NULL);\n"
         "    } else {\n"
         "        context_struct_compute_av(policydb, scontext, tcontext, tclass, avd, NULL);\n"
         "    }\n")
b_new = "    context_struct_compute_av_fn(policydb, scontext, tcontext, tclass, avd, NULL);\n"
if b_old in s:
    s = s.replace(b_old, b_new)
else:
    print("   note: guard #2 not present")

if "if (security_dump_masked_av_fn)" in s or "if (context_struct_compute_av_fn)" in s:
    sys.exit("ERROR: selinux_hide.c still has a function-pointer guard the compiler will reject")

if s == orig:
    print("   note: selinux_hide.c unchanged")
p.write_text(s)
PY
echo "   ok"

echo ">> local fix #2: pin KSU_VERSION in Kbuild"
python3 - "$KERNEL_TREE/drivers/kernelsu" "$KSU_VERSION" <<'PY'
import pathlib, sys
d = pathlib.Path(sys.argv[1])
ver = sys.argv[2]
p = d / "Kbuild"
s = p.read_text()

old = ('$(warning "KSU_GIT_VERSION not defined! It is better to make KernelSU a git repository!")\n'
       'ccflags-y += -DKSU_VERSION=16\n')
new = ('# A sandboxed copy of the tree (kleaf) has no .git, so the git-derived path\n'
       '# above never fires and KSU_VERSION would fall back to the sentinel 16, which\n'
       '# the manager reads as an ancient kernel. Pin the vendored revision instead:\n'
       '$(warning "KSU_GIT_VERSION not defined! Pinning the vendored revision instead")\n'
       f'KSU_VERSION ?= {ver}\n'
       'ccflags-y += -DKSU_VERSION=$(KSU_VERSION)\n')

if old not in s:
    sys.exit("ERROR: the KSU_VERSION sentinel block was not found in Kbuild; "
             "upstream changed, review the fix")
p.write_text(s.replace(old, new, 1))
PY
echo "   ok"

echo ">> updating the vendored-revision note in apex-patches/kernelsu/README.md"
python3 - "$PATCH_DIR/README.md" "$KSU_COMMIT" "$KSU_COMMITS" "$KSU_VERSION" <<'PY'
import pathlib, re, sys
p = pathlib.Path(sys.argv[1])
commit, commits, ver = sys.argv[2], sys.argv[3], sys.argv[4]
s = p.read_text()
new, n = re.subn(
    r"Vendored at commit `[^`]+` of `[^`]+` `[^`]+` \(\d+ commits,\s*reported as KSU_VERSION \d+\)\.",
    f"Vendored at commit `{commit}` of `tiann/KernelSU` `main` ({commits} commits,\n"
    f"reported as KSU_VERSION {ver}).",
    s)
if n:
    p.write_text(new)
    print(f"   updated {n} line(s)")
else:
    print("   note: revision line not found, README left as-is")
PY

echo ">> summary"
git -C "$KERNEL_TREE" --no-pager diff --stat -- \
    drivers/kernelsu drivers/uapi apex-patches/kernelsu/README.md | tail -6

CHANGED="$(git -C "$KERNEL_TREE" status --porcelain -- \
    drivers/kernelsu drivers/uapi apex-patches/kernelsu/README.md)"
if [ -z "$CHANGED" ]; then
    echo ">> already up to date, nothing changed"
    exit 3
fi

echo ">> done: KernelSU $KSU_COMMIT, KSU_VERSION $KSU_VERSION"
