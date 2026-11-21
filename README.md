# Advan X1 Upstream U-Boot Port (MediaTek MT6789 / Helio G99)

Clean, patch-series port of upstream **U-Boot** (base commit `c1958b5f6cce`) for the **Advan X1** (MediaTek MT6789 / Helio G99 / MT8781), designed to be chainloaded from stock Little Kernel via the **Loki** `loki_payload` subpartition (`0x210000`) at physical address `0x60000000`.

Every register address, clock table, memory window, framebuffer coordinate, and button mapping is derived directly from verified hardware facts in [`loki`](https://github.com/sysretq0/loki) and [`advan-x1-mainline`](https://github.com/sysretq0/advan-x1-mainline).

## Architecture

- **Execution Model**: Standalone position-independent AArch64 U-Boot (`CONFIG_POSITION_INDEPENDENT=y`, `CONFIG_TEXT_BASE=0x60000000`) running with ARM Trusted Firmware (BL31 @ `0x48200000`) resident in EL3 for PSCI (`CPU_ON`, `SYSTEM_RESET`, `SYSTEM_OFF`) and MediaTek SiP services (`MTK_SIP_KERNEL_UFS_CONTROL`).
- **Exception Level**: Supports both Non-Secure **EL1** (default stock `bl2_ext`) and Non-Secure **EL2** (when `loki pack --unlock-el2` is enabled for KVM).
- **Safe Physical Memory Map**: Explicitly leaves Secure EL3 (`BL31 @ 0x48200000`), TrustZone Kinibi TEE (`0x70000000..0x7FFFFFFF`), SSPM (`0x9FD60000`), SCP/SPM/MCUPM (`0xBF000000`), and RKP (`0xD0000000`) **unmapped** in `mt6789_mem_map[]`, preventing Cortex-A76 speculative prefetch SErrors. Relocation is clamped inside the verified-clean `0x60000000..0x6F000000` window.
- **Live Display Handoff**: `board_fix_fdt()` queries `OVL0_L0_ADDR` (`0x14005F40`) before DM video probe and patches `simple-framebuffer` (`1080×2460`, stride `4352` bytes, `a8r8g8b8`) to whichever double-buffer LK left active (`0xFE007000` or `0xFEA41000`).

## Enabled Subsystems

| Subsystem | Driver | Hardware / Notes |
|---|---|---|
| SoC & MMU | `arch/arm/mach-mediatek/mt6789/init.c` | TrustZone/MBLOCK-safe `mem_map`, PSCI reset |
| Clocks | `drivers/clk/mediatek/clk-mt6789.c` | `apmixedsys`, `topckgen`, `infracfg_ao` (from `advan-x1-mainline`) |
| Serial | `drivers/serial/serial_mtk.c` | UART0 @ `0x11002000` (921600 8N1) |
| Watchdog | `drivers/watchdog/mtk_wdt.c` | MT6789 RGU WDT @ `0x10007000` |
| Display | `drivers/video/simplefb.c` | Live OVL0 DSI video-mode scanout (`1080×2460`, `8x16` font) |
| Storage | `drivers/ufs/ufs-mediatek.c` | UFSHCI 2.2 @ `0x11270000`, SCSI, GPT, ext4, FAT |
| PMIC | `drivers/power/pmic/mtk-pwrap.c` | MT6789 pwrap @ `0x10026000` + MT6366/MT6358 |
| Buttons | `drivers/button/button-mtk-keys.c` | KPD VolDown (`0x10010000` bit 0) + PMIC Power/VolUp (`TOPSTATUS`) |
| USB Gadget | `drivers/usb/musb-new/mediatek.c` + `phy-mtk-tphy.c` | MUSB @ `0x11200000` + T-PHY @ `0x11F40000` (USB Fastboot) |
| Boot Flow | `bootstd` / `extlinux` / `booti` / `bootmenu` | Interactive on-screen menu controlled by phone buttons |

## Patch Series

1. `0001-arm-mediatek-Add-MT6789-Helio-G99-SoC-support.patch`
2. `0002-clk-mediatek-Add-MT6789-clock-driver-and-dt-bindings.patch`
3. `0003-power-pmic-mtk-pwrap-Add-MT6789-support.patch`
4. `0004-usb-musb-new-Add-generic-MediaTek-MUSB-glue-driver.patch`
5. `0005-button-Add-MediaTek-KPD-matrix-and-MT6358-MT6366-PMIC-key-.patch`
6. `0006-board-mediatek-Add-Advan-X1-MT6789-board-DTS-and-defconfig.patch`

## Building & Packing with Loki

```bash
# 1. Build u-boot.bin (verifies size fits in 0x210000..0x400000 LK subpartition)
./scripts/build.sh

# 2. Pack into verified lk_loki.img via Loki (from parent loki repo)
./loki pack devices/mt6789/advan_x1_v5.json \
    --lk /path/to/stock/lk.img \
    --payload uboot/build/u-boot.bin \
    -o build/lk_loki.img
```

## License

GPL-2.0-only (matching upstream U-Boot).
