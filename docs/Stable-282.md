![PLF110 144Hz](https://raw.githubusercontent.com/lenluxue/PLF110-Display-Overclock-LKM/main/assets/IMG_20261003_094440.jpg)

> lenluxue

# Stable-282 实现说明

正式包为维护者微调的 `PLF110-144-v1.12.2-Stable-282.zip`，版本 `1.12.2-144-Stable-282` / `versionCode=282`。
本次新增 WebUI 与统一亮度配置，KO 沿用 [281](Stable-281.md)，不改变链路、像素时钟、原厂档位、指纹或 HWC 时机。

## 应用刷新率 WebUI

`webui/` 对应发行包 `webroot/`，公开原始 HTML/CSS/JS 与 `api.sh`；不需要独立 APK。
KernelSU 的应用列表/图标接口提供已安装应用。只读 `src/Plf110PolicyReader.java` 从 ColorOS 服务读取
`DefaultRateList`、`RefreshRateList`、`NotSupportOverrideList`，mode3/index3 或 mode8/index4 与设置逻辑对应。
服务失败或超时则标记文件参考，页面规则单独显示，不把页面60Hz当成整个应用默认60Hz，不代表实时FPS。

默认值与手动覆盖分开；“自动”继承默认，手动筛选只统计手动设置。保存先备份用户覆盖XML，校验后原子替换，
保留无关条目；恢复使用首次WebUI修改前的备份。状态精简为“配置已同步”不改变数据来源或默认策略。

应用行/图标缓存，筛选只改变可见性；短按只走一次选择过渡，长按220ms后可左右拖动。
选中框按实际按钮尺寸定位，尺寸变化重测，视觉上移1px；默认/手动60绿色、90浅蓝、120金色、144粉红。
玻璃卡片与提示气泡包含半透明高光、边缘和backdrop blur，亮暗主题独立；支持时跳过离屏行渲染。
刷新单圈完成后停止，恢复弹窗有进退动画。弹层登记自己的history，网页边缘滑动可预览返回或取消。
这是网页交互，不是Android原生预测性返回；系统手势是否交付网页取决于管理器，不修改管理器。

界面不依赖ColorOS17私有视觉接口，ColorOS15/16也可在支持的管理器/WebView中呈现；不支持背景模糊则降级。
字体、效果和流畅度仍依宿主而异，不能由WebUI兼容性推导KO兼容其他机型/内核。

## 合并亮度配置

> 当超频出现亮度不同时可以参考

```ini
# companion/brightness.conf -> module root
gain=92
sync=1
curve=1:2664:88.4:93:98.5:1:2.0
```

`src/brightness_config.h` 验证完整三字段后一起更新；每秒热读，拒绝缺字段/重复/未知字段、非法值、NUL或过长文件。
缺失或编辑中无效文件保留最后有效配置。gain为70..100、步进0.1；100关闭衰减。
sync=0关闭内核同步，但沿用原有用户态回退含义，不等同停掉整个补偿。curve=0关闭曲线。
KO仍使用281的单次RAW补偿与同一整数曲线，未修改数学、黑位、HBM/OFP/指纹保护、停止恢复或更新顺序。

## 构建与边界

```sh
# 与281相同的Android/Bionic Clang 21.1.8；只构建，不运行worker
sh scripts/build_worker.sh
# javac 21、D8 9.2.4；只构建只读helper
sh scripts/build_policy_reader.sh
```

启动、更新、文件映射与恢复见 [282配套流程](Stable-282-Module.md)。不提交完整安装包、KO/worker/DEX二进制或外部工具链。
Zygisk二进制沿用原包，源码不在本仓库；这不是完整模块所有二进制的可复现声明。
之前完成配置解析/隔离API与JS模拟，本轮公开源文件与正式包逐字节比对、Shell语法与ZIP校验通过；公开入口重建的worker与DEX均与包内逐字节一致。
界面未做所有管理器/ROM的实机截图和帧率测量，亮度也不是光学标定，不保证所有场景一致。

## 正式资产

- ZIP：229897字节，SHA256 `5654418def0c84122d398212b95dcfd0bcd5c914c8ca16965ac33a5a48e60b11`。
- KO：SHA256 `80c4b4b07b0e4babd1a4d12faee097f0a1e79186521fc845a775ee60f2b9abaf`，与281相同。
