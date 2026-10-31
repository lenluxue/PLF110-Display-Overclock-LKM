# PLF110 Display Overclock · 144Hz

[中文](README_CN.md) · [Download](https://github.com/lenluxue/PLF110-Display-Overclock-LKM/releases/latest) · [Changelog](docs/changelog-history.md)

![PLF110 144Hz](assets/IMG_20261003_094440.jpg)

Runtime display overclocking for the OnePlus Ace 5 Racing Edition (PLF110), AA600 panel.
Adds a 144Hz mode while keeping stock modes and fingerprint support at 144Hz.
No DTBO modification or stock panel-driver replacement.

## Install

Install the stable release ZIP with KernelSU or another compatible root manager, then reboot manually.
The module reloads HWC once after Android finishes booting to expose the added mode.
Future updates are available through the manager.

## Current release

**Stable-281**: 1399Mbps link at 144Hz; normal backlight requests are compensated once before sending. Brightness-dependent curve with endpoint correction; default base gain: 92%.
App policy defaults: regular apps 120Hz, short-video apps 60Hz, listed games 144Hz, with selected gacha games excluded.
Installable packages are kept in Releases; this repository contains source and documentation.

## Compatibility and risks

PLF110 / MT6989 baseline; tested software environments include ColorOS 17 and ColorOS 16.1.
The installer accepts 6.1.157, 6.1.134, 6.1.118 and 6.1.115; matching these numbers does not prove ABI compatibility.

Overclocking may cause flicker, corruption, black screens or boot failures. Keep a way to disable the module.
The brightness gain is a device-specific visual calibration, not a guarantee across all brightness, HDR and fingerprint states.

## Source and credits

- [Stable-281 implementation](docs/Stable-281.md)
- [Build and ABI reference](docs/Reference-build.md)
- [Companion flow](docs/Stable-281-Module.md)
- [Changelog archive](docs/changelog-history.md)

Thanks to [Yunnijian/MTK-Display-Overclock-LKM](https://github.com/Yunnijian/MTK-Display-Overclock-LKM),
original author Smartisan_Apple_Kt, [OnePlusOSS](https://github.com/OnePlusOSS), and MediaTek.

Author: **lenluxue** · [GPL-2.0-only](LICENSE) · [Provenance](NOTICE)
