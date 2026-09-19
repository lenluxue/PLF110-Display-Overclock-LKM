# ColorOS 144Hz 应用策略接入

这个目录记录 PLF110 配套 root 模块需要提供的最小属性。它不能替代 LKM，
也不应单独用于没有真实 144Hz DRM 模式的设备。

## 为什么系统已经识别 144Hz，应用设置仍只有 120Hz

ColorOS 16 的设置程序会从 `Display.getSupportedModes()` 构造可用档位，因此
内核和 Android 显示缓存必须先真实包含 144Hz。随后
`ScreenRefreshAppPreference` 还会读取：

```text
ro.oplus.refreshrate.maxsettings
```

刷新率 ID 对应关系为：

| ID | 刷新率 |
| ---: | ---: |
| 1 | 90Hz |
| 2 | 60Hz |
| 3 | 120Hz |
| 4 | 144Hz |
| 7 | 165Hz |

PLF110 原厂没有 `oplus.software.performance.enable_high_refresh_rate`
feature。若应用默认上限不是 ID 4，设置程序会从自定义应用刷新率列表移除
144Hz，即使 `dumpsys display` 已经能看到该模式。

配套模块必须在 Zygote 启动前通过 `system.prop` 设置：

```properties
ro.oplus.refreshrate.maxsettings=4
```

这样设置程序会把 ID 4 作为设备原生最高应用档位保留下来。现有 Zygisk
system_server 桥仍负责同步 ColorOS/Android 的运行时上限；无需修改 Settings
APK、注入应用白名单或替换原厂完整 XML。

## 必要前提

启用该属性前应同时满足：

- LKM 的 `modes` 中存在 `1080x2392@144`；
- `dumpsys display` 的 supported modes 中存在约 144Hz 的真实模式；
- 基于当前 `/my_product/etc/refresh_rate_config.xml` 生成的运行时配置含
  `maxrefreshsettings="4"` 与 `defaultMaxRate="144"`；
- ColorOS 常量仍定义 144Hz 为原生 ID 4。

若任何一项不满足，不能只靠该属性伪造 144Hz。

## 验证

重启后可在终端检查：

```sh
getprop ro.oplus.refreshrate.maxsettings
cat /sys/module/PLF110_Display_OC/parameters/modes
dumpsys display | grep -E '144|supportedModes|supportedRefreshRates'
grep -o 'maxrefreshsettings="[^"]*"\|defaultMaxRate="[^"]*"' \
  /data/system/refresh_rate_config.xml | head
```

第一条应输出 `4`。最终功能仍需进入 ColorOS 的自定义应用刷新率页面，确认
目标应用能选择 144Hz，并用实际游戏帧率验证。
