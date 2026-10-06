![PLF110 144Hz](https://raw.githubusercontent.com/lenluxue/PLF110-Display-Overclock-LKM/main/assets/IMG_20261003_094440.jpg)

> lenluxue

## [1.12.1-Stable-273] - 2026-10-06

### Fixed
- 修复旧版使用不存在的 `/sys/kernel/thermal/gpt`，导致 GPU 温度限频关闭未生效的问题。
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
