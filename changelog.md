![PLF110 144Hz](https://raw.githubusercontent.com/lenluxue/PLF110-Display-Overclock-LKM/main/assets/IMG_20261003_094440.jpg)

> lenluxue

## [1.12.1-Stable-268] - 2026-10-05

### Added
- 合并 MTK Perf 配置，原作者：toolfor
- 音量键安装配置Mtk Perf：GPU 温度限频和峰值功耗限制可分别选择
- 检测是否安装独立 mtk_temp 模块；检测到时请求 KernelSU 卸载后再安装合并版

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
