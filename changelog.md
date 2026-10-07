![PLF110 144Hz](https://raw.githubusercontent.com/lenluxue/PLF110-Display-Overclock-LKM/main/assets/IMG_20261003_094440.jpg)

> lenluxue

## [1.12.1-Stable-277] - 2026-10-07

### Fixed
- 修复部分已在设置中指定 144Hz 的应用，在下拉控制中心或切换窗口后被 120Hz 请求压制、无法恢复 144Hz 的问题。
- 切换路径和初始化参数统一为 1375Mbps，目标实测约 145Hz。

### Verified
- SHA-256：`ad2bc6a627f5cd05c556e2e0c8807a380c86ded3c099e49cb0091a69455924b3`。

## [1.12.1-Stable-275] - 2026-10-07

### Changed
- 将 144Hz 模式的 DSI 链路调整为 1375Mbps（按 145Hz 链路推算）；其他刷新率策略、应用刷新率配置和 MTK Perf 配置保持不变。

### Verified
- 基于 `PLF110-144-v1.12.1-Stable-274.zip` 原始 KO 仅替换 144Hz 链路常量，并通过模块静态检查、脚本语法检查、ZIP 完整性检查和基准包逐文件保留校验。
- 资产 SHA-256：`d30ec033ec24499bf01c561bc279bb440b9b7093b2328fb94365b7f459d0e45f`。
- 解决了提出问题的人。

## [1.12.1-Stable-274] - 2026-10-06

### Fixed
- 修复了会导致超频失效的 bug：
1.进入系统后不重启 vendor HWC 服务
2.注入的 144Hz 档位没有被显示栈采用
- 修复后每次开机都会在系统启动完成、开机动画停止之后，强制重启一次 `vendor.hwcomposer-3-2`；每次开机只重启一次，且不会在开机动画期间动手，避免出现卡第一屏。

### Changed
- 不再用 `hwc_reload.disabled` 拦截自动重启，历史残留文件不会继续挡住这次修复。
- 二游（原神、崩坏 3、星穹铁道、绝区零、鸣潮、明日方舟、碧蓝航线、FGO、公主连结、阴阳师等 24 个包）不再纳入 144Hz 游戏策略，回落到普通应用 120Hz。
- OEM 游戏区间会把整段游戏包批量写成 144Hz，所以额外在写入后覆盖回 120Hz，用户级刷新率覆盖文件里的旧 144Hz 记录也会一并清掉。
- /data/local/tmp/plf110-capture 的启动取证日志在服务启动时清理一次，之后每 24 小时清理一次；只删除该目录第一层超过 24 小时的普通文件，保留新日志和目录结构。

### Verified
- 资产 SHA-256：`3b62a8cb4c54f2d3e35368e80c2f4ba22d680db8cd4703653f875cd3b1dbde05`。

- 解决了提出问题的人。

## [1.12.1-Stable-273] - 2026-10-06

### Fixed
- 修复MTK Perf使用不存在的 `/sys/kernel/thermal/gpt`，导致 GPU 温度限频关闭未生效的问题。
- 改用 `/proc/gpufreqv2/limit_table`，按 `THERMAL_AP` / `THERMAL_EB` 名称动态识别 limiter，并关闭 GPU 温度 ceiling。
- 修正 PPB 状态回读判断，避免 `ppb_mode: 2` 与 `mode 2` 格式差异导致每秒重复写入。

### Compatibility
- 已对 Android 15 / Android 16 的 MT6989 公开内核模块源码进行复核，关键 GPU limiter 接口一致。
- 不固定 limiter ID；没有 gpufreqv2 接口时回退旧 `/sys/kernel/thermal/gpt` 节点。
- 已在 Android 16、内核 `6.1.157` 实机刷入重启验证：GPU 温控 `THERMAL_AP` / `THERMAL_EB` 的 `c_enable=0`，PPB 为 `ppb_mode: 2`。

### Verified
- 144Hz LKM 状态：`installed=1`、`hooks=3/3`、`modes=5`、`validation_failures=0`。
- 资产 SHA-256：`ae08ad9936d606a2c524c327127d543ac8f1167d95fb2b29c168740a24faa191`。

## [1.12.1-Stable-268] - 2026-10-05

### Added
- 合并 MTK Perf 配置，原作者：toolfor
- 添加配置Mtk Perf：GPU 温度限频和峰值功耗限制可分别选择
- 检测是否已有独立 mtk_temp 模块；检测到时请求
root管理器卸载后再安装合并版

### Changed
- 保留 MTK Perf 的 ODM 性能与温控配置

### Compatibility
- 仅支持 PLF110；安装后请手动重启设备
- GPU 温度限频和峰值功耗选项默认保持关闭状态

## [1.12.1-Stable-267] - 2026-10-05

### Added
- KernelSU Manager 更新日志加入远程图片渲染测试
- 应用刷新率策略：普通应用 120Hz、短视频 60Hz、游戏 144Hz
- 全部游戏写入自定义应用刷新率的 144Hz 预设（原厂游戏区 + 扩展名单，共 174 个包）
### Fixed
- ColorOS 在开机后把 `peak_refresh_rate` 改回 120，导致游戏实际只能到 120Hz；现于开机完成后的启动窗口内自动恢复 144Hz 上限
### Changed
- 用户刷新率覆盖 XML 改为单次批量改写，避免 `post-fs-data` 阶段为每个游戏启动独立进程
### Compatibility
- 非游戏应用与用户已有的自定义刷新率选择保持不变
- 用户覆盖原文件在模块状态目录保留备份，卸载模块时恢复

## [1.12.1-Stable-251] - 2026-10-03
### Fixed
- 解决了提出问题的人
### Changed
- 更新版本号
### Compatibility
- 我怎么知道
