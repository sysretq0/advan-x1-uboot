#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
#
# Advan X1 (MediaTek MT6789 / Helio G99) clean upstream U-Boot build pipeline.
# Applies patches/ cleanly onto pristine upstream U-Boot (pinned base commit)
# and produces u-boot.bin sized to fit inside the Loki LK subpartition (0x210000..0x400000).
#
# Usage:
#   ./scripts/build.sh              # Build u-boot.bin on worktree
#   ./scripts/build.sh verify       # Verify all patches apply cleanly + checkpatch
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
UPSTREAM="${UPSTREAM:-$REPO/../u-boot-upstream}"
WORK="${WORK:-$REPO/../u-boot-worktree}"
OUT="${OUT:-$REPO/build}"
BASE_COMMIT="c1958b5f6cce03956d309ce422b5d9f819955d4a"
JOBS="${JOBS:-1}"
MODE="${1:-build}"

# Max payload capacity inside 4 MiB lk.img subpartition at 0x210000 (Advan X1):
# LOKI_SUBPART_MAX_PAYLOAD = 0x400000 - 0x210000 - 512 (mkimg) - 64 (loki_subpart_header)
#                          = 2,031,040 bytes (0x1EFDC0).
# Cap U-Boot at 1.875 MiB (1,966,080 B) leaving 64 KiB headroom on Advan X1.
# Note: other MT6789 profiles with higher subpart_offset (e.g. 0x260000 ->
# LOKI_SUBPART_MAX_PAYLOAD = 1,703,360 B) enforce their own lower bound in loki pack.
MAX_UBOOT_BYTES=1966080

if [ ! -d "$UPSTREAM/.git" ]; then
    echo "[*] Cloning pristine upstream U-Boot..."
    git init "$UPSTREAM"
    git -C "$UPSTREAM" remote add origin https://github.com/u-boot/u-boot.git
    git -C "$UPSTREAM" fetch --depth 1 origin "$BASE_COMMIT"
    git -C "$UPSTREAM" checkout --detach FETCH_HEAD
fi

if [ ! -e "$WORK/.git" ]; then
    git -C "$UPSTREAM" worktree prune
    rm -rf "$WORK"
    git -C "$UPSTREAM" worktree add --detach "$WORK" "$BASE_COMMIT"
else
    git -C "$WORK" reset --hard HEAD
    git -C "$WORK" clean -fdx
    if git -C "$WORK" rev-parse --verify "${BASE_COMMIT}^{commit}" >/dev/null 2>&1; then
        git -C "$WORK" checkout --detach "$BASE_COMMIT"
    else
        git -C "$WORK" checkout --detach "$(git -C "$UPSTREAM" rev-parse HEAD)"
    fi
fi

echo "== Applying patch series onto pristine upstream U-Boot =="
PATCH_COUNT=0
for p in "$REPO"/patches/*.patch; do
    [ -e "$p" ] || { echo "No patches found!"; exit 1; }
    echo "  apply $(basename "$p")"
    git -C "$WORK" apply --whitespace=error "$p"
    PATCH_COUNT=$((PATCH_COUNT + 1))
done
echo "== Applied $PATCH_COUNT patches cleanly =="

echo "== Checking DTS & defconfig sync against patched tree =="
diff -u "$REPO/dts/mt6789.dtsi" "$WORK/arch/arm/dts/mt6789.dtsi"
diff -u "$REPO/dts/mt6789-advan-x1.dts" "$WORK/arch/arm/dts/mt6789-advan-x1.dts"
diff -u "$REPO/configs/mt6789_advan_x1_defconfig" "$WORK/configs/mt6789_advan_x1_defconfig"
echo "== DTS & defconfig sync: OK (zero drift) =="

if [ "$MODE" = "verify" ]; then
    if [ -x "$WORK/scripts/checkpatch.pl" ]; then
        echo "== Running U-Boot checkpatch.pl =="
        for p in "$REPO"/patches/*.patch; do
            perl "$WORK/scripts/checkpatch.pl" --no-tree --quiet "$p" || {
                echo "checkpatch flagged $(basename "$p"):"
                perl "$WORK/scripts/checkpatch.pl" --no-tree "$p" | grep -E "ERROR:|CHECK:" && exit 1 || true
            }
        done
    fi
    echo "== Verification OK ($PATCH_COUNT patches) =="
    exit 0
fi

mkdir -p "$OUT"
if [ "$(uname -m)" != "aarch64" ]; then
    export CROSS_COMPILE="${CROSS_COMPILE:-aarch64-linux-gnu-}"
fi

echo "== Configuring mt6789_advan_x1_defconfig =="
make -C "$WORK" O="$OUT" mt6789_advan_x1_defconfig

echo "== Building u-boot.bin (-j$JOBS) =="
make -C "$WORK" O="$OUT" -j"$JOBS"

UBOOT_BIN="$OUT/u-boot.bin"
SIZE=$(wc -c < "$UBOOT_BIN")
echo "== Built $UBOOT_BIN ($SIZE bytes) =="
if [ "$SIZE" -gt "$MAX_UBOOT_BYTES" ]; then
    echo "FATAL: u-boot.bin ($SIZE bytes) exceeds Loki subpartition cap ($MAX_UBOOT_BYTES bytes)!"
    exit 1
fi
(cd "$OUT" && sha256sum u-boot.bin u-boot.dtb > sha256sums.txt && cat sha256sums.txt)
echo "== Build OK (fits cleanly in Loki 0x210000 subpartition) =="
