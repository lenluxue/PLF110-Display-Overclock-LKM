# Stable-280 配套模块流程

对照正式280 ZIP，版本 `1.12.1-144-Stable-280` / `versionCode=280`。
亮度算法见 [280实现说明](Stable-280.md)，原配置细节见 [278历史流程](Stable-278-Module.md)。

## 文件分工

| 文件 | 分工 |
| --- | --- |
| `module.prop` / `customize.sh` | 正式版本、更新入口、内核小版本检查、音量键确认和权限 |
| `PLF110_Display_OC.ko` | 原厂模式保留、144注入/链路切换、指纹兼容、切档与普通背光单次补偿 |
| `post-fs-data.sh` | OEM配置备份/生成、分档及游戏用户覆盖、开机守卫、短时注入 |
| `service.sh` | 注入重试、开机完成后一次HWC重载、原有刷新率守护、启动亮度worker及日志清理 |
| `bin/plf110-brightness-comp` | 请求/保护/所有权维护、增益热读、live能力识别及回退 |
| `brightness_gain.conf` / `brightness_sync.conf` | 默认93% / 同步启用1；worker在系统就绪后应用 |
| `system.prop` / feature XML / `zygisk/` | 保留包内原设置菜单和组件配置；Zygisk实现源码不在本仓库 |
| `action.sh` / `uninstall.sh` | 状态输出、恢复原XML、清理模块状态并提示重启 |

## 安装、启动与更新

安装入口仍接受6.1.157/6.1.134/6.1.118/6.1.115，音量上确认、下取消；
小版本相符不证明厂商ABI、CRC或CFI兼容。刷入后由用户手动重启。

1. `post-fs-data` 从当前 `/my_product/etc/refresh_rate_config.xml` 生成副本，
   验证后写 `/data/system/refresh_rate_config.xml`，不手写完整系统XML。
2. 两类XML首次修改前备份；普通120、短视频60、游戏名单144，二游排除；
   游戏显式选择写入 `refresh_rate_config_user_override.xml`。不保证游戏引擎输出144fps。
3. feature文件显式bind到同路径已有目标，不挂载整个 `/data/system` 或 `/my_product`。
4. 早期KO仅短时注入尝试，未完成交service重试；配置记录本次boot ID pending。
5. 系统 `sys.boot_completed=1` 且动画停止后接受配置、清pending并留lastgood。
   前次未完成则下次回退OEM基线并禁用自动分档，这是配置守卫而非所有卡屏自动恢复。
6. SurfaceFlinger与vendor HWC就绪后，按boot ID仅重载一次 `vendor.hwcomposer-3-2`；
   不重启SurfaceFlinger，不重启整机，不在开机动画期间操作HWC。
7. 框架识别144且worker可用后，service启动亮度维护。worker先读取原请求及保护，
   再应用gain/sync并回读live能力；正常背光由KO发送前单次处理，不再依赖事后反复补写。
   钩子不可用时仍使用旧回退路径，可能保留原闪亮问题。

原全局144上限启动维护和按前台/用户选择启用请求优先级的守护沿用，
不是所有应用强制144；本包没有按ColorOS版本自动移除这些步骤。

管理器 `update.json` 为280，ZIP指向GitHub正式资产；`changelog` 直接读取
`docs/changelog-history.md` 的raw Markdown（含头图与完整历史）。根 `changelog.md`
只作历史日志入口，不再维护第二份正文；不要用Markdown重定向页作为管理器正文。
三端仓库及发行包同步，旧279安装用户可按更高versionCode收到更新。

## 检查与恢复

状态入口在 `/sys/module/PLF110_Display_OC/parameters/`，原 `status/modes` 检查注入；
`brightness_sync_status` 检查 `enabled/live/live_error/live_fixed`。
计数和背光缓存不代表物理扫描/光学测试。亮度系数支持0.1%调节，
新KO必须重启加载，仅HWC重载不能更换已驻留的内核模块。

主日志超过512KiB保留最近1000行；capture启动取证保留原900秒timeout。
`/data/local/tmp/plf110-capture/` 启动清一次、之后每86400秒清理第一层超24小时普通文件。
不递归删除子目录，工具/权限不齐不保证早期故障落盘。

卸载按初次备份恢复两类刷新率XML，原本不存在则删除，并清理模块状态目录。
worker停止按原所有权规则恢复背光；内核回调持有自身引用，禁用/卸载后
需手动重启完成恢复，不能强制热卸载KO。本次发布不自动刷入或重启设备。
