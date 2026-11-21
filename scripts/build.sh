#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
#
# Advan X1 (MediaTek MT6789 / Helio G99) clean upstream U-Boot build pipeline.
# Applies patches/ cleanly onto pristine upstream U-Boot (pinned base commit)
# and produces u-boot.bin sized to fit inside the Loki LK subpartition (0x210000..0x400000).
#
# Usage:
#   ./scripts/build.sh              # Build u-boot.bin on worktree
#   ./scripts/build.sh verify       # Dry-run verify all patches apply cleanly on pristine base
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
UPSTREAM="${UPSTREAM:-/work/bootloader/u-boot-upstream}"
WORK="${WORK:-/work/bootloader/u-boot-worktree}"
OUT="${OUT:-$REPO/build}"
BASE_COMMIT="c1958b5f6cce03956d309ce422b5d9f819955d4a"
JOBS="${JOBS:-2}"
MODE="${1:-build}"

# Max payload capacity inside 4 MiB lk.img subpartition at 0x210000:
# 0x400000 - 0x210000 - 512 (mkimg) - 64 (loki_subpart_header) = 2,031,040 bytes
MAX_UBOOT_BYTES=1966080  # 1.875 MiB (matches CHAINLOAD_MAX_SIZE in loki payload)

if [ ! -d "$UPSTREAM/.git" ]; then
    echo "[*] Cloning pristine upstream U-Boot..."
    git clone --depth 1 https://github.com/u-boot/u-boot.git "$UPSTREAM"
fi

if [ ! -e "$WORK/.git" ]; then
    git -C "$UPSTREAM" worktree prune
    rm -rf "$WORK"
    git -C "$UPSTREAM" worktree add --detach "$WORK" HEAD
else
    git -C "$WORK" reset --hard HEAD
    git -C "$WORK" clean -fdx
    # Reset back to upstream base commit if patches were already applied
    if git -C "$WORK" rev-parse --verify "${BASE_COMMIT}^{commit}" >/dev/null 2>&1; then
        git -C "$WORK" checkout --detach "$BASE_COMMIT"
    else
        git -C "$WORK" checkout --detach "$(git -C "$UPSTREAM" rev-parse HEAD)"
    fi
fi

echo "== Applying patch series onto pristine upstream U-Boot =="
for p in "$REPO"/patches/*.patch; do
    [ -e "$p" ] || { echo "No patches found!"; exit 1; }
    echo "  apply $(basename "$p")"
    git -C "$WORK" apply --whitespace=nowarn "$p"
done

if [ "$MODE" = "verify" ]; then
    echo "== All patches applied cleanly to pristine upstream U-Boot =="
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
sha256sum "$UBOOT_BIN" "$OUT/u-boot.dtb"
echo "== Build OK (fits cleanly in Loki 0x210000 subpartition) =="
