# PLF110 屏幕超频 · 144Hz

[English](README.md) · [下载](https://github.com/lenluxue/PLF110-Display-Overclock-LKM/releases/latest) · [更新日志](changelog.md)

![PLF110 144Hz](assets/IMG_20261003_094440.jpg)

一加 Ace 5 竞速版（PLF110）AA600 面板的运行时超频模块。
新增 144Hz 档位，保留原厂刷新率，支持 144Hz 下使用指纹。
不修改 DTBO，不替换原厂面板驱动。

## 安装

使用 KernelSU 等 root 管理器安装正式发行版 ZIP，然后手动重启。
系统启动完成后，模块自动重载一次 HWC，使新增档位生效。
后续可通过管理器更新。

## 当前版本

**Stable-279**：144Hz 链路 1399Mbps；切档亮度补偿默认 86.5%，支持 0.1% 调节。
普通应用默认 120Hz、短视频 60Hz、游戏名单 144Hz，部分二游排除。
完整安装包仅放在发行版，仓库保留源码和说明。

## 兼容与风险

基线为 PLF110 / MT6989，已验证系统环境包含 ColorOS 17、ColorOS 16.1。
安装入口接受 6.1.157、6.1.134、6.1.118、6.1.115；小版本一致不代表 ABI 一定兼容。
ColorOS 17 不必另写旧版“系统接管”适配，但本包仍保留原有策略。

超频有闪屏、花屏、黑屏和启动失败风险；请保留禁用模块的恢复方式。
亮度系数是本机观感校准值，不保证所有亮度、HDR、指纹场景完全一致。

## 源码与致谢

- [Stable-279 实现说明](docs/Stable-279.md)
- [构建与 ABI 参考](docs/Reference-build_CN.md)
- [配套模块流程](docs/Stable-278-Module.md)（279 沿用，亮度扩展见上文）
- [历史更新日志](docs/changelog-history.md)

感谢 [Yunnijian/MTK-Display-Overclock-LKM](https://github.com/Yunnijian/MTK-Display-Overclock-LKM)、
原作者 Smartisan_Apple_Kt、[OnePlusOSS](https://github.com/OnePlusOSS) 和 MediaTek。

作者：**lenluxue** · [GPL-2.0-only](LICENSE) · [来源说明](NOTICE)
