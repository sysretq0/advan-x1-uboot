# Advan X1 Upstream U-Boot Port (MediaTek MT6789 / Helio G99)

Clean, upstream-grade patch series on pristine **U-Boot** (base commit `c1958b5f6cce`) for the **Advan X1** (MediaTek MT6789 / Helio G99 / MT8781), chainloaded from stock Little Kernel via the **Loki** `loki_payload` subpartition (`0x210000`) at physical address `0x60000000`.

## Architecture

- **Execution Model**: Standalone position-independent AArch64 U-Boot (`CONFIG_POSITION_INDEPENDENT=y`, `CONFIG_TEXT_BASE=0x60000000`) running with ARM Trusted Firmware (BL31 @ `0x48200000`) resident in EL3 for PSCI (`CPU_ON`, `SYSTEM_RESET`, `SYSTEM_OFF`) and MediaTek SiP services (`MTK_SIP_KERNEL_UFS_CONTROL`).
- **Exception Level**: Supports both Non-Secure **EL1** and Non-Secure **EL2** (handed off via ATF BL31 `MTK_SIP_KERNEL_BOOT_AARCH64`).
- **Safe Physical Memory Map**: Explicitly leaves Secure EL3 (`BL31 @ 0x48200000`), TrustZone Kinibi TEE (`0x70000000..0x7FFFFFFF`), SSPM (`0x9FD60000`), SCP/SPM/MCUPM (`0xBF000000`), and RKP (`0xD0000000`) **unmapped** in `mt6789_mem_map[]`, preventing Cortex-A76 speculative prefetch SErrors. Relocation is clamped inside the clean `0x60000000..0x6F000000` window.
- **Live Display Handoff**: `board_fix_fdt()` queries `OVL0_L0_ADDR` (`0x14005F40`) before DM video probe, clears prior-stage overlay planes to transparent (`alpha=0`), and patches `simple-framebuffer` (`1080×2460`, stride `4352` bytes, `a8r8g8b8`) in-place to the active scanout buffer.

## Enabled Subsystems

| Subsystem | Driver | Hardware / Notes |
|---|---|---|
| SoC & MMU | `arch/arm/mach-mediatek/mt6789/` | TrustZone/EMI-MPU-safe `mem_map`, `lowlevel_init.S`, PSCI sysreset |
| Clocks | `drivers/clk/mediatek/clk-mt6789.c` | `apmixedsys`, `topckgen`, `infracfg_ao` (synced with Linux MT6789 bindings) |
| Serial | `drivers/serial/serial_mtk.c` | UART0 @ `0x11002000` (921600 8N1) with gated-UART detection |
| Watchdog | `drivers/watchdog/mtk_wdt.c` | MT6789 RGU WDT @ `0x10007000` |
| Display | `drivers/video/simplefb.c` | `VIDEO_A8R8G8B8` opaque alpha (`1080×2460`, `16x32` font) + padded-stride EFI GOP |
| Storage | `drivers/ufs/ufs-mediatek.c` | UFSHCI 2.2 @ `0x11270000` with `UFSHCD_QUIRK_KEEP_LINK_ACTIVE`, SCSI, GPT, ext4, FAT |
| PMIC | `drivers/power/pmic/mtk-pwrap.c` | MT6789 pwrap @ `0x10026000` + MT6366/MT6358 + standard `keys` child binding |
| Buttons | `drivers/button/button-mtk-keys.c` | Standard `mediatek,mt6779-keypad` (`linux,keymap`) + `mediatek,mt6358-keys` (`power`/`home`) |
| USB Gadget | `drivers/usb/musb-new/mediatek.c` + `phy-mtk-tphy.c` | MUSB @ `0x11200000` + T-PHY @ `0x11F40000` (USB Fastboot) |
| Boot Flow | `bootstd` / `FIT` / `extlinux` / `bootmenu` | Interactive phone-button menu (`linux_boot` FIT priority + UEFI + Fastboot) |

## Patch Series

1. `0001-dt-bindings-clock-mediatek-Add-MT6789-clock-and-rese.patch`
2. `0002-arm-mediatek-Add-MT6789-Helio-G99-SoC-support.patch`
3. `0003-clk-mediatek-Add-MT6789-clock-driver.patch`
4. `0004-power-pmic-mtk-pwrap-Add-MT6789-support-and-bind-PMI.patch`
5. `0005-usb-musb-new-Add-generic-MediaTek-MUSB-glue-driver.patch`
6. `0006-button-Add-MediaTek-keypad-and-MT6358-PMIC-key-drive.patch`
7. `0007-serial-mtk-Enable-clocks-before-init-and-avoid-hangi.patch`
8. `0008-video-Add-VIDEO_A8R8G8B8-format-for-opaque-alpha-fra.patch`
9. `0009-efi_loader-gop-Respect-video-line_length-stride-and-.patch`
10. `0010-ufs-mediatek-Fix-PA_SCRAMBLING-write-and-guard-optio.patch`
11. `0011-ufs-Guard-unallocated-UTMRL-and-harden-UTP-command-c.patch`
12. `0012-ufs-Add-UFSHCD_QUIRK_KEEP_LINK_ACTIVE-for-pre-initia.patch`
13. `0013-arm-dts-mediatek-Add-MT6789-SoC-device-tree.patch`
14. `0014-board-mediatek-Add-Advan-X1-MT6789-board-support.patch`
15. `0015-disk-part_efi-Reject-out-of-bounds-GPT-partition-ent.patch`
16. `0016-boot-bootdev-Support-up-to-MAX_SEARCH_PARTITIONS-and.patch`

## Verifying, Building & Packing with Loki

```bash
# 1. Verify clean apply + checkpatch compliance on pristine upstream U-Boot
./scripts/build.sh verify

# 2. Build u-boot.bin (verifies size fits in 0x210000..0x400000 LK subpartition)
./scripts/build.sh

# 3. Pack into verified lk_loki.img via Loki (from parent loki repo)
./loki pack devices/mt6789/advan_x1_v5.json \
    --lk /path/to/stock/lk.img \
    --payload uboot/build/u-boot.bin \
    -o build/lk_loki_advan_x1_v5.img
```

## License

GPL-2.0-only (matching upstream U-Boot; DT binding headers dual-licensed `GPL-2.0-only OR BSD-2-Clause`).
