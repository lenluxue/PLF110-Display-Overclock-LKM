# ColorOS per-app 144 Hz integration

This directory documents the minimum property required by the PLF110 companion
root module. It does not replace the LKM and must not be used on a device that
does not expose a real 144 Hz DRM mode.

**ColorOS 17:** according to the maintainer's PLF110 usage, the ColorOS 16
policy integration described below can be skipped. KO injection and display
mode enumeration are still required. The existing Stable-278 ZIP does not
automatically disable its old policy steps on ColorOS 17.

The settings/property path below applies to ColorOS 16. See the
[complete companion notes](../docs/Stable-278-Module.md) for release behavior.

ColorOS 16 first builds its refresh-rate list from
`Display.getSupportedModes()`. Its `ScreenRefreshAppPreference` then reads
`ro.oplus.refreshrate.maxsettings`. Native rate IDs on this build are 1=90,
2=60, 3=120, 4=144, and 7=165.

PLF110 does not ship the
`oplus.software.performance.enable_high_refresh_rate` feature. If the default
per-app ceiling is not ID 4, Settings removes 144 Hz from the per-app menu even
when `dumpsys display` already reports it. The companion module therefore sets:

```properties
ro.oplus.refreshrate.maxsettings=4
```

The property is loaded before Zygote and works alongside the release's feature
configuration to retain the 144 Hz menu. The complete companion package also
generates an OEM-derived XML, updates selected app entries, and maintains
runtime caps. It does not patch the Settings APK.

Use it only when the LKM mode list, Android display cache, and the OEM-derived
runtime XML all expose the real 144 Hz / ID 4 mode. After reboot, verify the
property with `getprop ro.oplus.refreshrate.maxsettings`, inspect
`dumpsys display`, and confirm the option in ColorOS's per-app refresh-rate UI.
