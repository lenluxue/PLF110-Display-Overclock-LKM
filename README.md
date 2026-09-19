# MTK Display Overclock LKM: PLF110 144 Hz Reference

中文说明：[README_CN.md](README_CN.md)

License: [GPL-2.0-only](LICENSE)

This repository documents a runtime 144 Hz LKM for the OnePlus Ace 5 Racing
Edition (PLF110) and its AA600 video-mode panel. It does not replace DTBO or the
stock panel driver. It appends one validated 144 Hz DRM mode while preserving
the stock 60/90/120/30 Hz modes and the original ColorOS VRR/ADFR, fingerprint,
HBM, brightness, DSC, and ESD paths.

> [!WARNING]
> Display overclocking can cause green tint, flicker, split-screen corruption,
> DSI timeouts, a black screen, or a boot failure. This code targets the exact
> ABI below. A matching device name or kernel major version is not sufficient.

## Acknowledgements

Sincere thanks to:

- [Yunnijian/MTK-Display-Overclock-LKM](https://github.com/Yunnijian/MTK-Display-Overclock-LKM),
  whose public PMB110 reference supplied the project structure, defensive
  validation ideas, KCFI/ABI guidance, and build organization used here.
- `Smartisan_Apple_Kt`, named as the author in that PMB110 reference source.
- [OnePlusOSS](https://github.com/OnePlusOSS) and MediaTek for publishing the
  GPL kernel, vendor-module, and display-driver sources used to establish the
  PLF110 ABI.

This is a GPL-2.0-only derivative implementation. Upstream provenance is also
recorded in [NOTICE](NOTICE).

## Validated baseline

| Item | Baseline |
| --- | --- |
| Product | OnePlus Ace 5 Racing Edition / PLF110 |
| Device | `OP60F9L1` |
| SoC | MediaTek MT6989 |
| Panel driver | `aa600_p_3_a0025_vdo_panel` |
| Primary DSI | `1420a000.dsi0` |
| Tested software | ColorOS 16.1 / Android 16 environment |
| Kernel release | `6.1.157-android14-11-o-gc2dad16af736` |
| OnePlus branch | `oneplus/mt6989_b_16.0.0_ace5_race` |
| Kernel commit | `822beed40827f1e9a103bc06ab4714a670080b72` |
| Modules/device-tree commit | `d60d564c82de298fe4909657c31c29c73ba25aba` |
| Validated module compiler | Clang 21.1.8 |

The corresponding public repositories are
`OnePlusOSS/android_kernel_oneplus_mt6989` and
`OnePlusOSS/android_kernel_modules_and_devicetree_oneplus_mt6989`.

## Timings

The stock AA600 driver creates four modes dynamically. The added mode clones
the complete stock 120 Hz `mtk_panel_params` and DDIC command path, then changes
only the host timing and dynamic MIPI parameters.

| Mode | Pixel clock | H display/start/end/total | V display/start/end/total | Link |
| --- | ---: | --- | --- | ---: |
| 60 Hz | 387072 kHz | 1080/1260/1264/1280 | 2392/4984/4986/5040 | stock 1162 Mbps |
| 90 Hz | 387072 kHz | 1080/1260/1264/1280 | 2392/3304/3306/3360 | stock 1162 Mbps |
| 120 Hz | 387072 kHz | 1080/1260/1264/1280 | 2392/2464/2466/2520 | stock 1162 Mbps |
| 30 Hz | 241920 kHz | 1080/3180/3184/3200 | 2392/2464/2466/2520 | stock 1162 Mbps |
| 144 Hz | 464486 kHz | 1080/1209/1213/1229 | 2392/2569/2571/2625 | dynamic 1395 Mbps |

The nominal host refresh is:

```text
464486000 / (1229 * 2625) = 143.976 Hz
```

The custom dynamic parameters are `VSA/VBP/VFP=2/54/177`,
`HSA/HBP/HFP=4/16/129`, `data_rate=1395`, and
`dyn_fps.vact_timing_fps=144`. Top-level stock PLL/data-rate, DSC, DDIC, ESD,
fingerprint, and brightness data remain cloned from the original 120 Hz mode.

## Design

PLF110 cannot use the PMB110 panel-array technique directly. Its stock panel
driver creates modes in `lcm_get_modes()`, so this implementation:

1. Captures the primary `mtk_dsi` from read-only probes and a platform-device
   scan.
2. Validates the exact panel driver, all four stock timings, the base link, the
   ext parameters, and callback KCFI type IDs before modifying pointers.
3. Clones the stock 120 Hz mode and its complete `mtk_panel_params`.
4. Copies the panel and connector function tables, wrapping only `get_modes`
   and `fill_modes` to append and order the custom mode.
5. Wraps `ext_param_set/get`; a 144 Hz request first travels through the stock
   120 Hz DDIC path, then selects the cloned 144 Hz host parameters.
6. Installs `mode_switch_update_for_vdo` to switch MIPI hopping to 1395 Mbps on
   entry and back to 1162 Mbps on exit, with post-switch state validation.
7. Rebuilds the MTK connector/CRTC mode cache and emits a DRM hotplug event.
8. Holds a module reference while callbacks are installed so live function
   pointers cannot be unloaded.

No unverified DCS command is introduced. Reusing the stable 120 Hz DDIC path is
intentional and reduces the risk of fingerprint, low-brightness, and HBM
regressions.

## Build

Use `scripts/build_module.sh` with the exact generated headers, OnePlus kernel
source, vendor display source, and validated toolchain:

```sh
export PLF110_HEADERS_DIR=/path/to/generated-kheaders
export PLF110_KERNEL_SOURCE=/path/to/android_kernel_oneplus_mt6989
export PLF110_DISPLAY_ROOT=/path/to/android_kernel_modules_and_devicetree_oneplus_mt6989/kernel/kernel_device_modules-6.1
export PLF110_CLANG=/path/to/clang/bin/clang
export PLF110_LD_LLD=/path/to/clang/bin/ld.lld
sh scripts/build_module.sh
sh scripts/check_module.sh
```

The output is `out/PLF110_144_Mode.ko`; its default in-kernel name is
`PLF110_Display_OC`. The checker verifies ELF architecture, vermagic, module
identity, attribution, the imported-symbol allowlist and CRC records, KCFI
indirect-call instrumentation, and the validated timing/link constants.

The large OnePlusOSS trees are external inputs and are not vendored here.

## Runtime interface

The module loads disabled and exposes:

```text
/sys/module/PLF110_Display_OC/parameters/enable
/sys/module/PLF110_Display_OC/parameters/refresh
/sys/module/PLF110_Display_OC/parameters/status
/sys/module/PLF110_Display_OC/parameters/modes
```

Example:

```sh
insmod PLF110_144_Mode.ko
cat /sys/module/PLF110_Display_OC/parameters/status
echo 1 > /sys/module/PLF110_Display_OC/parameters/enable
cat /sys/module/PLF110_Display_OC/parameters/modes
```

A healthy installation reports `installed=1`, `captured=1`, and `modes=5`,
and lists `1080x2392@144`.

## ColorOS policy integration

The LKM makes 144 Hz real in DRM/MTK. ColorOS smart-mode ownership also depends
on its refresh-rate XML and Android rendering caps. A companion root module
should copy the current device's `/my_product/etc/refresh_rate_config.xml` on
every boot and modify only the maximum/default fields after validation. It
must preserve OEM app, scene, VRR, and ADFR rules and restore the previous
runtime file on uninstall. Its `system.prop` should also set
`ro.oplus.refreshrate.maxsettings=4`, which keeps the native 144 Hz / ID 4
entry in ColorOS's per-app refresh-rate menu. Do not ship a hand-written
replacement XML.

That property does not invent a display mode. It is valid only after DRM,
Android's display cache, and the ColorOS configuration all expose the real
ID 4 mode. See [companion/README.md](companion/README.md) for the framework
decision path and verification notes.

## ABI notes

- `PLF110_VERMAGIC` must match the full target kernel release and config.
- The embedded `__versions` CRC values belong only to the validated kernel.
- KCFI requires matching callback prototypes, feature macros, headers, and
  compiler behavior.
- `mtk_dsi`, `mtk_panel_params`, and `mtk_panel_funcs` are private vendor ABI,
  not stable interfaces.
- Successful compilation does not prove runtime compatibility.

## Validation and recovery

Test every direction among 60/90/120/144 Hz, low brightness, AOD, fingerprint,
local HBM, orientation changes, game windows, suspend/resume, and charging.
Inspect dmesg for DSI timeouts, underflow, KCFI failures, and validation errors.

If the panel splits, flashes green, stays black, or boot loops, disable/remove
the root module from KernelSU/Magisk safe mode and reboot. Preserve pstore,
dmesg, and the `status`/`modes` output for diagnosis.

The installed callbacks pin the LKM for the current boot. Rebooting after
disable or uninstall is the reliable recovery path.
