# Advan X1 Upstream U-Boot Port (MediaTek MT6789 / Helio G99)

Clean, upstream-grade patch series on pristine **U-Boot** (base commit `c1958b5f6cce`) for the **Advan X1** (MediaTek MT6789 / Helio G99 / MT8781), chainloaded from stock Little Kernel via the **Loki** `loki_payload` subpartition (`0x210000`) at physical address `0x60000000`.

## Architecture

- **Execution Model**: Standalone position-independent AArch64 U-Boot (`CONFIG_POSITION_INDEPENDENT=y`, `CONFIG_TEXT_BASE=0x60000000`) running with ARM Trusted Firmware (BL31 @ `0x48200000`) resident in EL3 for PSCI (`CPU_ON`, `SYSTEM_RESET`, `SYSTEM_OFF`) and MediaTek SiP services (`MTK_SIP_UFS_CONTROL`).
- **Exception Level**: Supports both Non-Secure **EL1** and Non-Secure **EL2** (handed off via ATF BL31 `MTK_SIP_KERNEL_BOOT_AARCH64`).
- **Safe Physical Memory Map & Full 8 GiB Linux Handoff**: Explicitly leaves Secure EL3 (`BL31 @ 0x48200000`), TrustZone Kinibi TEE (`0x70000000..0x76BFFFFF`), SSPM, SCP/SPM/MCUPM, RKP, and modem windows **unmapped** in `mt6789_mem_map[]` to prevent Cortex-A76 speculative prefetch SErrors. U-Boot relocation is clamped inside `0x60000000..0x6F000000`, the Fastboot buffer lives separately at `0x52000000..0x59FFFFFF` (zero overlap with kernel/FIT staging), and `# CONFIG_ARCH_FIXUP_FDT_MEMORY is not set` preserves Linux's FIT DTB `/memory@40000000` (full 8 GiB minus stock `no-map` carveouts = ~7.69 GiB usable).
- **Physical Display Handover (LK → U-Boot → Kernel)**: `board_fix_fdt()` queries `OVL0_L0_ADDR` (`0x14005F40`) before DM video probe, fills the active plane opaque black / secondary planes transparent (`alpha=0`), and patches U-Boot's own `simple-framebuffer` (`1080×2460`, stride `4352` bytes, `a8r8g8b8`) in-place for U-Boot's console and EFI GOP. Linux boots its own FIT DTB via `boot.scr` + `bootm` (no simplefb DTB splice to Linux) and halts LK/U-Boot OVL0 splash DMA cleanly on `mediatek-drm` probe.
- **Boot & Reboot Modes**: `bootmenu_0` launches mainline Linux via `bootflow scan -lb` → `boot.scr` → SHA-256 FIT `bootm`. `fastboot_set_reboot_flag()` writes `WDT_NONRST_REG2` (`0x10007024`, mask `0x0f`: `recovery=0x02`, `bootloader=0x03`), matching mainline Linux `syscon-reboot-mode`.

## Enabled Subsystems

| Subsystem | Driver | Hardware / Notes |
|---|---|---|
| SoC & MMU | `arch/arm/mach-mediatek/mt6789/` | TrustZone-safe `mem_map` (3 clean banks), `lowlevel_init.S`, PSCI sysreset |
| Clocks | `drivers/clk/mediatek/clk-mt6789.c` | `apmixedsys`, `topckgen`, `infracfg_ao` (synced with Linux MT6789 bindings) |
| Serial | `drivers/serial/serial_mtk.c` | UART0 @ `0x11002000` (`921600 8N1`, matching PL/LK/BL31) with gated-UART guard |
| Watchdog | `drivers/watchdog/mtk_wdt.c` | MT6789 RGU WDT @ `0x10007000` + `WDT_NONRST_REG2` (`0x24`) fastboot reboot flags |
| Display | `drivers/video/simplefb.c` | `VIDEO_A8R8G8B8` opaque alpha (`1080×2460`, `16x32` font) + padded-stride EFI GOP |
| Storage | `drivers/ufs/ufs-mediatek.c` | UFSHCI 2.2 @ `0x11270000` (`UFSHCD_QUIRK_KEEP_LINK_ACTIVE` for LK handoff; relies on LK-enabled `vemc`), SCSI, 128-part GPT, ext4, FAT |
| PMIC | `drivers/power/pmic/mtk-pwrap.c` | Native `mt6789_regs[]` (`INT_EN=0x450`) @ `0x10026000` + MT6366/MT6358 + `keys` child |
| Buttons | `drivers/button/button-mtk-keys.c` | Standard `mediatek,mt6779-keypad` (`linux,keymap`) + `mediatek,mt6358-keys` (`power`/`home`) |
| USB Gadget | `drivers/usb/musb-new/mediatek.c` + `phy-mtk-tphy.c` | MUSB @ `0x11200000` + `mediatek,mt6789-tphy` cold-wake/OTG force (Fastboot @ `0x52000000` + CDC-ACM) |
| Boot Flow | `bootstd` / `FIT` / `extlinux` / `bootmenu` | Interactive phone-button menu (`boot.scr` FIT `bootm` + UEFI + Fastboot) |

## Patch Series (17 patches)

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
17. `0017-phy-mediatek-tphy-Add-MT6789-USB2-PHY-wakeup-and-OTG.patch`

## Verifying, Building & Packing with Loki

```bash
# 1. Verify clean apply, DTS/defconfig zero-drift, and checkpatch compliance
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
