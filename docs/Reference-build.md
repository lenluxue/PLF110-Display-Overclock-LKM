# MTK Display Overclock LKM: PLF110 144 Hz Reference

中文说明：[README_CN.md](../README_CN.md)

![Project image](../assets/IMG_20261003_094440.jpg)

License: [GPL-2.0-only](../LICENSE)

This repository documents a runtime 144 Hz LKM for the OnePlus Ace 5 Racing
Edition (PLF110) and its AA600 video-mode panel. It does not replace DTBO or the
stock panel driver. It appends one validated 144 Hz DRM mode while preserving
the stock 60/90/120/30 Hz modes and the original ColorOS VRR/ADFR, fingerprint,
HBM, brightness, DSC, and ESD paths.

The current reference is Stable-278: 464486 kHz pixel clock and a 1399 Mbps
custom link. See [Stable-278 KO implementation notes](../docs/Stable-278-KO.md)
for the release hashes, callback flow, and companion HWC refresh sequence.

Fingerprint recognition and unlocking work while the display uses the 144 Hz
mode. The OFP/HBM compatibility hook selects the stock 120 Hz panel profile
locally; it leaves the DRM 144 Hz mode intact. Installation, configuration,
boot guards, log retention, and uninstall behavior are documented in
[Stable-278 companion module notes](../docs/Stable-278-Module.md).

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
recorded in [NOTICE](../NOTICE).

## Validated baseline

| Item | Baseline |
| --- | --- |
| Product | OnePlus Ace 5 Racing Edition / PLF110 |
| Device | `OP60F9L1` |
| SoC | MediaTek MT6989 |
| Panel driver | `aa600_p_3_a0025_vdo_panel` |
| Primary DSI | `1420a000.dsi0` |
| Tested software | ColorOS 17 / ColorOS 16.1 / Android 16 environments |
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
| 144 Hz | 464486 kHz | 1080/1209/1213/1229 | 2392/2569/2571/2625 | dynamic 1399 Mbps |

The nominal host refresh is:

```text
464486000 / (1229 * 2625) = 143.976 Hz
```

The custom dynamic parameters are `VSA/VBP/VFP=2/54/177`,
`HSA/HBP/HFP=4/16/129`, `data_rate=1399`, and
`dyn_fps.vact_timing_fps=120`. The DRM timing describes the custom 144 Hz
mode; the vendor panel profile remains on its stock 120 Hz path.
Top-level stock PLL/data-rate, DSC, DDIC, ESD,
fingerprint, and brightness data remain cloned from the original 120 Hz mode.

## Design

PLF110 cannot use the PMB110 panel-array technique directly. Its stock panel
driver creates modes in `lcm_get_modes()`, so this implementation:

1. Captures the panel's `mtk_dsi` through the `drm_panel_get_modes` and
   `mtk_dsi_porch_setting` probes, after checking the panel identity.
   Module initialization does not scan the platform bus.
2. Validates the exact panel driver, all four stock timings, the base link, the
   ext parameters, and callback KCFI type IDs before modifying pointers.
3. Clones the stock 120 Hz mode and its complete `mtk_panel_params`.
4. Copies the panel and connector function tables, wrapping only `get_modes`
   and `fill_modes` to append and order the custom mode.
5. Wraps `ext_param_set/get`; a 144 Hz request first travels through the stock
   120 Hz DDIC path, then selects the cloned 144 Hz host parameters.
6. Installs `mode_switch_update_for_vdo` to switch MIPI hopping to 1399 Mbps on
   entry and back to 1162 Mbps on exit, with post-switch state validation.
7. Rebuilds the MTK connector/CRTC mode cache and emits a DRM hotplug event.
8. Holds a module reference while callbacks are installed so live function
   pointers cannot be unloaded.

The KO rebuilds kernel mode caches. Stable-278's companion `service.sh` then
waits for `sys.boot_completed=1` and a stopped boot animation before restarting
`vendor.hwcomposer-3-2` once per boot, so HWC re-enumerates the injected mode.

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

## ColorOS versions

Current package flow: [Stable-280](Stable-280-Module.md). The historical integration below documents the property/configuration mechanism, not an automatic ROM-version branch.

<details>
<summary>ColorOS 16: policy integration and historical release behavior</summary>

The LKM makes 144 Hz real in DRM/MTK. ColorOS smart-mode ownership also depends
on its refresh-rate XML and Android rendering caps. A companion root module
copies the current device's `/my_product/etc/refresh_rate_config.xml` on
every boot, updates the maximum/default fields and selected app entries,
and validates the result. It keeps unmodified OEM scene, VRR, and ADFR rules
and restores the previous
runtime file on uninstall. Its `system.prop` should also set
`ro.oplus.refreshrate.maxsettings=4`, which keeps the native 144 Hz / ID 4
entry in ColorOS's per-app refresh-rate menu. Do not ship a hand-written
replacement XML.

The companion module's historical implementation:

- keeps the global cap at 144 Hz: ColorOS rewrites `peak_refresh_rate` back to
  120 shortly after boot, after which DisplayModeDirector clamps every 144 Hz
  XML entry back to 120, so the cap is re-applied during the boot window;
- splits apps by policy: 120 Hz default (`3-1-2-3`), 60 Hz for short-video apps
  (`2-2-2-2`) and 144 Hz for games (`4-1-2-3`);
- writes `0-0-0-4` into `/data/system/refresh_rate_config_user_override.xml`
  for games that only unlock their own high-frame-rate option once the per-app
  refresh rate is set to 144 Hz (the four fields are auto / 90 / 60 / 120);
- tracks apps assigned 144 Hz by the generated XML or a manual user choice,
  enabling ColorOS's app-request priority while those apps are foreground.
  This helps the app recover from a 120 Hz vote after a notification shade or
  window transition; ordinary apps keep their existing 120/60 Hz policy.

The user override file is backed up before the first write and restored on
uninstall. `update.json` points the root manager at the newest release asset.

That property does not invent a display mode. It is valid only after DRM,
Android's display cache, and the ColorOS configuration all expose the real
ID 4 mode. See [companion/README.md](../companion/README.md) for the framework
decision path and verification notes.

</details>

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
