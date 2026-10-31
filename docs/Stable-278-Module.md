# Stable-278 配套模块说明

> 历史版本说明；当前实现见 [Stable-281](Stable-281.md) 与 [配套流程](Stable-281-Module.md)。

本文对照正式 `PLF110-144-v1.12.1-Stable-278.zip` 的实际文件整理。
KO 参数和回调实现见 [Stable-278 KO 实现说明](Stable-278-KO.md)。
以下描述已有发行包的行为，未修改安装包。

## 功能与系统版本

模块增加 144Hz 显示模式，保留原厂 60/90/120/30Hz 模式，支持在 144Hz 下
使用屏下指纹识别和解锁。指纹与亮度复用原厂面板配置，OFP 的局部 120Hz
返回值用于兼容，不代表整个 DRM 显示模式已降为 120Hz。

本历史包没有按ColorOS版本自动跳过配置和请求守护；兼容性取决于实际ABI。

## 文件分工

| 文件 | 作用 |
| --- | --- |
| `module.prop` | 模块 ID、作者、版本 278 和管理器更新地址 |
| `customize.sh` | 安装时内核小版本检查、音量键确认和权限设置 |
| `PLF110_Display_OC.ko` | 运行时模式注入、动态链路切换与指纹兼容 |
| `post-fs-data.sh` | 早期配置准备、备份、应用策略、启动守卫及短时注入尝试 |
| `service.sh` | 注入重试、系统完成后 HWC 刷新、历史请求守护和日志清理 |
| `action.sh` | 管理器“操作”按钮的设备、档位和配置识别状态输出 |
| `uninstall.sh` | 恢复两类用户空间配置及清理模块状态目录 |
| `system.prop` | 原厂刷新率切换及自定义应用最高档位属性 |
| `my_product/etc/permissions/oplus.product.display_features.xml` | 设置菜单相关的显示 feature 配置 |
| `zygisk/arm64-v8a.so` | 包内现有的 Zygisk 组件；本仓库未提供其实现源码 |

## 安装与更新

安装脚本接受 `6.1.157 / 6.1.134 / 6.1.118 / 6.1.115` 四个内核小版本，
再用音量上键确认安装、下键取消；默认等待 10 秒，超时或无法读取按键时取消。
这一检查只是安装入口，并不能单独证明符号 CRC、KCFI 或厂商结构体 ABI 一致。

包内版本为 `1.12.1-144-Stable-278`，`versionCode=278`。
管理器根据 `update.json` 的 `versionCode`、`zipUrl`、`changelog` 检查更新；
发行 ZIP 和 Markdown 更新日志由 GitHub 提供，其他仓库同步保留相同实现资料。

安装后手动重启使启动脚本和显示缓存重新生效。模块脚本会在本次系统启动
完成后重启一次 vendor HWC 服务，不会主动重启整台设备。

## 配置文件与挂载

| 源 / 状态文件 | 目标 / 用途 |
| --- | --- |
| `/my_product/etc/refresh_rate_config.xml` | 每次开机读取当前 OEM 配置作为生成基线 |
| `/data/system/refresh_rate_config.xml` | 验证后写入生成的最高档位和应用策略 |
| `/data/system/refresh_rate_config_user_override.xml` | 部分游戏的显式 144Hz 用户选择 |
| 模块内 `my_product/etc/permissions/oplus.product.display_features.xml` | 显式 bind 到系统同路径的已有 feature 文件 |
| `/data/adb/plf110_display_oc/` | 原配置备份、模式来源缓存、启动标记及守卫状态 |

刷新率 XML 的处理是从 OEM 文件生成副本，再替换 `/data/system` 下的目标文件；
`post-fs-data.sh` 的显式 bind 操作针对 feature 文件，而非整个 `/data/system`
或整个 `/my_product` 目录。源/目标 feature 文件缺失时记录日志并跳过该挂载。

两类用户空间配置均在首次修改前记录原文件是否存在，并保存可用原文件。
生成文件经过字段和应用条目检查；最终文件设置为 `system:system`、权限 0600，
并尝试恢复 `system_data_file` 的 SELinux 标签。

## 历史应用策略

| 类别 | 目标 | 策略值 |
| --- | --- | --- |
| 普通应用 | 默认 120Hz | `3-1-2-3` |
| 短视频名单 | 默认 60Hz | `2-2-2-2` |
| OEM 游戏区间及扩展游戏名单 | 默认 144Hz | `4-1-2-3` |
| 二游排除名单 | 普通应用的 120Hz | `3-1-2-3`，并移除其生成的游戏用户覆盖条目 |
| SystemUI | 保留 144Hz 请求 | `4-1-2-3` |

游戏名单结合 OEM 区间和扩展包名，去重后批量写入 `0-0-0-4` 用户覆盖值，
用于部分只有显式选择 144Hz 才显示高帧率选项的游戏。区间标记缺失时使用
显式名单。名单仅表示系统刷新率策略，不能保证游戏引擎实际输出 144fps。

`service.sh` 维护启动阶段的全局最高刷新率，并按前台窗口和用户 144Hz 选择
切换 ColorOS 的应用请求优先级。普通应用、短视频、窗口切换和 SystemUI
并非一律强制全局 144Hz。以上是278历史包的实际实现。

## 开机守卫与 HWC

早期注入只进行短时尝试；没有捕获 DSI 或注入尚未完成时交给 service 重试。
应用配置生效前记录本次 boot ID。service 等待 `sys.boot_completed=1` 且
`init.svc.bootanim=stopped` 后接受配置，清除 pending 标记并保留 lastgood 副本。

若下一轮发现上次不同 boot ID 的 pending 未被接受，配置流程退回 OEM 基线
及最高档位修改，写入 `policy.disabled`，停止自动应用分档。这是配置守卫，
不是对所有内核故障或卡屏情况的自动修复保证。

HWC 刷新须同时满足系统启动完成、动画停止、SurfaceFlinger 存在及
`vendor.hwcomposer-3-2` 正在运行，随后按 boot ID 只重启一次该 vendor 服务。
历史 `hwc_reload.disabled` 不拦截 278 的此次刷新；不重启 SurfaceFlinger，
也不在开机动画期间触发 HWC 刷新。

## 状态与日志

管理器“操作”按钮输出模块版本、机型、系统版本、内核与框架档位识别情况，
以及设置菜单 feature / OEM 来源 ID。它不负责改写档位，也不是实际帧率计。

主日志 `/data/adb/plf110_display_oc.log` 在启动脚本入口检查大小，超过
512KiB 时保留最近 1000 行。启动诊断在 `/data/local/tmp/plf110-capture/`
短时采集 logcat 和 dmesg，使用 900 秒 timeout；logcat 带自身轮转参数。

service 启动时清理一次 capture 目录，之后每 86400 秒再清理一次，
仅处理该目录第一层超过 24 小时的普通文件，保留子目录结构。
日志采集依赖系统权限和工具是否可用，不能保证卡屏或早期内核故障一定落盘。

## 卸载恢复

`uninstall.sh` 根据状态恢复刷新率 XML 和用户覆盖 XML 的原始备份；
安装前原本不存在的目标文件则删除。随后清理模块状态目录。
恢复的是首次修改前保存的文件，模块启用期间后续修改不构成新的原始备份。

文件挂载与已经安装的内核回调在当前开机期间可能仍存在；KO 安装回调后持有
自身引用，因此禁用或卸载后需要手动重启完成恢复。
本次文档整理不修改设备配置、安装包或启动服务。
