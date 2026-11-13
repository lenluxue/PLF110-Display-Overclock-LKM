![PLF110 144Hz](https://raw.githubusercontent.com/lenluxue/PLF110-Display-Overclock-LKM/main/assets/IMG_20261003_094440.jpg)

> lenluxue

# Stable-282 配套模块流程

维护者指定原包直接发布，不改包不重打包。KO及原HWC/刷新率启动流程保持281基线。

| 仓库来源 | 发行包目标 |
| --- | --- |
| `companion/module.prop`、安装/启动/卸载脚本、`system.prop`、`brightness.conf` | 模块根目录 |
| `companion/my_product/` | `my_product/` |
| `webui/` | `webroot/` |
| `src/Plf110PolicyReader.java` + `scripts/build_policy_reader.sh` | `bin/plf110-policy-reader.dex` |
| `src/brightness_comp.c` + `scripts/build_worker.sh` | `bin/plf110-brightness-comp` |
| 281的亮度扩展构建输入 | `PLF110_Display_OC.ko`，本次未改 |

`companion/` 是配套脚本源码，不是完整安装模块；安装包仍只在Releases，不新建 `module/`。
内核入口仍接受6.1.157/6.1.134/6.1.118/6.1.115，音量确认和ABI风险说明不变。
安装/更新后由用户手动重启；系统启动完成后一次HWC重载，保留原OEM XML生成、游戏覆盖与开机守卫。
WebUI的保存不会替换KO；只改静态界面后退出重开即可。新的KO或worker安装则仍需重启。

`brightness.conf` 取代三份旧亮度conf，service以同一路径启动worker；热调配置无需重载HWC。
WebUI首写单独备份用户覆盖XML；保存与恢复保持校验和原子替换，页面不改内核时序或全局亮度设置。
默认来自系统服务或明确标注的文件参考，不为了显示60Hz制造手动覆盖。

管理器继续使用原 `updateJson`；`update.json` 的 `versionCode=282` 高于281，ZIP直指GitHub正式资产。
`changelog` 仍读取 `docs/changelog-history.md` 的raw完整历史，顶部图片和lenluxue保留。
先验证三端282附件可下载，再推进main更新入口，避免用户收到指向未就绪资产的更新。

日志清理、HWC时机与卸载恢复沿用[281流程](Stable-281-Module.md)；不强制热卸载KO，不自动重启设备。
首次XML备份与WebUI备份用途不同，详情以公开的同版本脚本为准。
