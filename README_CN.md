# MTK 屏幕超频 LKM：PLF110 144Hz 参考实现

English: [README.md](README.md)

许可证：[GPL-2.0-only](LICENSE)

本项目是一加 Ace 5 竞速版（PLF110）AA600 面板的运行时 144Hz LKM
参考实现。模块不替换 DTBO、不覆盖原厂面板驱动，也不伪造 150/165Hz 档位；
它在 MTK DRM 显示栈运行时追加一个经过设备实测的 144Hz 模式，并让原厂
60/90/120/30Hz 模式、指纹、高亮度模式以及 ColorOS 的 VRR/ADFR 管理接口
继续沿用原始驱动。

> [!WARNING]
> 屏幕超频存在花屏、闪屏、绿屏、显示链路超时、无法亮屏甚至设备无法正常
> 启动的风险。本代码只对应下述精确软件与内核 ABI。相同机型换内核、换 ROM
> 或更新厂商显示驱动后，也必须重新核对并重新编译。

## 致谢

这个项目能够整理成可审阅源码，离不开以下公开项目和作者：

- [Yunnijian/MTK-Display-Overclock-LKM](https://github.com/Yunnijian/MTK-Display-Overclock-LKM)：
  提供了 MTK 显示超频 LKM 的公开参考结构、安全校验思路、KCFI/ABI 说明与
  构建组织方式。
- `Smartisan_Apple_Kt`：上述 PMB110 参考源码中标注的原作者。
- [OnePlusOSS](https://github.com/OnePlusOSS) 与 MediaTek：提供 PLF110 对应的
  GPL 内核、设备模块和显示驱动源码基础。

本仓库是 GPL-2.0-only 衍生实现，保留上游许可证与来源说明。感谢原项目作者
愿意公开成果，让后续设备适配可以建立在可复核代码上，而不是只留下二进制。

## 已验证基线

| 项目 | 基线 |
| --- | --- |
| 产品型号 | 一加 Ace 5 竞速版 / PLF110 |
| 设备代号 | `OP60F9L1` |
| SoC | MediaTek MT6989 |
| 面板驱动 | `aa600_p_3_a0025_vdo_panel` |
| DSI 设备 | `1420a000.dsi0` |
| 系统 | ColorOS 16.1 / Android 16 测试环境 |
| 内核 | `6.1.157-android14-11-o-gc2dad16af736` |
| OnePlus 内核分支 | `oneplus/mt6989_b_16.0.0_ace5_race` |
| 内核源码提交 | `822beed40827f1e9a103bc06ab4714a670080b72` |
| 模块/设备树提交 | `d60d564c82de298fe4909657c31c29c73ba25aba` |
| 编译器 | Clang 21.1.8（与已验证模块产物一致） |

只匹配 `6.1.157` 这个数字远远不够。完整 release 后缀、内核配置、符号 CRC、
厂商结构体布局、KCFI 类型哈希和显示驱动提交都属于 ABI 的一部分。

对应官方仓库：

- `OnePlusOSS/android_kernel_oneplus_mt6989`
- `OnePlusOSS/android_kernel_modules_and_devicetree_oneplus_mt6989`

## 原厂模式与新增模式

原厂 AA600 驱动动态创建 60/90/120/30Hz 四个模式。144Hz 模式复制原厂
120Hz 的完整 `mtk_panel_params` 和 DDIC 刷新命令路径，只改变主机显示时序与
动态 MIPI 参数。

| 模式 | Pixel clock | H timing | V timing | 链路 |
| --- | ---: | --- | --- | ---: |
| 60Hz | 387072 kHz | 1080/1260/1264/1280 | 2392/4984/4986/5040 | 原厂 1162 Mbps |
| 90Hz | 387072 kHz | 1080/1260/1264/1280 | 2392/3304/3306/3360 | 原厂 1162 Mbps |
| 120Hz | 387072 kHz | 1080/1260/1264/1280 | 2392/2464/2466/2520 | 原厂 1162 Mbps |
| 30Hz | 241920 kHz | 1080/3180/3184/3200 | 2392/2464/2466/2520 | 原厂 1162 Mbps |
| 144Hz | 464486 kHz | 1080/1209/1213/1229 | 2392/2569/2571/2625 | 动态 1395 Mbps |

表中时序顺序分别为：

```text
H: hdisplay / hsync_start / hsync_end / htotal
V: vdisplay / vsync_start / vsync_end / vtotal
```

144Hz 的主机侧理论刷新率为：

```text
464486000 / (1229 × 2625) ≈ 143.976 Hz
```

动态参数为：

```text
switch_en = 1
data_rate = 1395 Mbps
vsa/vbp/vfp = 2/54/177
hsa/hbp/hfp = 4/16/129
dyn_fps.vact_timing_fps = 144
```

顶层 `pll_clk=581`、`data_rate=1162` 和原厂 DSC/ESD/指纹/HBM 配置保持不变；
进入 144Hz 时通过 MTK `MIPI_HOPPING` 切到 1395Mbps，离开 144Hz 时恢复
1162Mbps。DDIC 仍执行已验证的 120Hz 命令表，而不是发送自造的面板命令。

## 实现原理

PLF110 与 PMB110 的面板数据结构不同，不能只替换设备名。原厂 AA600 驱动在
`lcm_get_modes()` 中调用 `drm_mode_duplicate()` 动态创建模式，因此本实现使用
以下路径：

1. 在 `drm_panel_get_modes` 与 `mtk_dsi_porch_setting` 上安装只读 kprobe，
   同时扫描平台设备 `1420a000.dsi0`，捕获主 DSI 实例。
2. 检查面板驱动名、原厂四个模式的完整 H/V 时序、像素时钟、基础链路、
   `mtk_panel_params` 和 callback KCFI 类型。
3. 复制原厂 120Hz 模式与完整 ext 参数，构造一个独立 144Hz 模式；任何基线
   不一致都会返回错误，不继续写入回调。
4. 复制 `drm_panel_funcs` 与 `drm_connector_funcs`，只替换 `get_modes` 和
   `fill_modes`；在原厂回调结束后追加 144Hz，并固定顺序为
   60/90/120/30/144。
5. 包装 `ext_param_set/get`。当目标为 144Hz 时，先让原厂逻辑按 120Hz 更新
   DDIC 状态，再把 DSI ext 参数指向 144Hz 副本。
6. 提供 `mode_switch_update_for_vdo`，只在进入或离开 144Hz 时执行动态
   MIPI hopping，并校验实际 `data_rate` 与 hopping 状态。
7. 调用 MTK 的 connector/CRTC 重建接口并发送 DRM hotplug，使 Android 显示栈
   重新读取五个模式；不重启 SurfaceFlinger/HWC。
8. 回调安装后增加模块自身引用，避免仍在执行的内核函数指针被强行卸载。

## 为什么仍然复用 120Hz DDIC 路径

面板寄存器命令和主机输出时序不是一回事。原厂 AA600 已经有稳定的 120Hz
DDIC 初始化、指纹局部 HBM、亮度和 ESD 路径；144Hz 只增加主机输出频率和链路
带宽。这样可以减少低亮度发绿、切档亮度变化、指纹失效和未知 DCS 命令带来的
风险。

“系统显示 144”也不等于硬件确实输出 144Hz。应结合 DRM mode、DSI 数据率、
可靠的帧计数器和实际应用帧率验证。

## 编译

唯一入口为 `scripts/build_module.sh`。构建需要精确对应的外部输入，仓库不复制
OnePlusOSS 的大型源码树。

| 环境变量 | 内容 |
| --- | --- |
| `PLF110_HEADERS_DIR` | 目标设备生成内核头，至少包含 generated config、UAPI 与 arm64 generated headers |
| `PLF110_KERNEL_SOURCE` | 对应 OnePlus 内核源码树，需包含 `scripts/module.lds.S` |
| `PLF110_DISPLAY_ROOT` | 对应模块仓库中的 `kernel/kernel_device_modules-6.1` |
| `PLF110_CLANG` | Clang 21.1.8 的 `clang` |
| `PLF110_LD_LLD` | 同套工具链的 `ld.lld` |

示例：

```sh
export PLF110_HEADERS_DIR=/path/to/plf110-generated-kheaders
export PLF110_KERNEL_SOURCE=/path/to/android_kernel_oneplus_mt6989
export PLF110_DISPLAY_ROOT=/path/to/android_kernel_modules_and_devicetree_oneplus_mt6989/kernel/kernel_device_modules-6.1
export PLF110_CLANG=/path/to/clang/bin/clang
export PLF110_LD_LLD=/path/to/clang/bin/ld.lld
sh scripts/build_module.sh
sh scripts/check_module.sh
```

成功产物为 `out/PLF110_144_Mode.ko`，内核内部模块名默认为
`PLF110_Display_OC`。检查脚本会验证 ELF 架构、vermagic、模块名、许可证、
作者信息、外部符号白名单、每个导入符号的 CRC、KCFI 间接调用保护，以及
源码中的已验证 144Hz 时序与 1395Mbps 链路常量。

## 运行接口

模块默认只捕获 DSI，不立即安装 144Hz。对应 sysfs：

```text
/sys/module/PLF110_Display_OC/parameters/enable
/sys/module/PLF110_Display_OC/parameters/refresh
/sys/module/PLF110_Display_OC/parameters/status
/sys/module/PLF110_Display_OC/parameters/modes
```

典型流程：

```sh
insmod PLF110_144_Mode.ko
cat /sys/module/PLF110_Display_OC/parameters/status
echo 1 > /sys/module/PLF110_Display_OC/parameters/enable
cat /sys/module/PLF110_Display_OC/parameters/modes
```

`status` 应出现 `installed=1`、`captured=1`、`modes=5`；`modes` 中应出现
`1080x2392@144`。如果检查失败，不要反复写 `enable=1`，先保存 dmesg 和状态。

## ColorOS 系统接管

LKM 只负责让内核 DRM/MTK 显示栈真实拥有 144Hz。ColorOS 是否把它作为智能
最高档，还取决于系统自己的刷新率配置和 DisplayModeDirector 上限。

配套模块应在每次开机时：

1. 从设备当前 `/my_product/etc/refresh_rate_config.xml` 复制原厂文件；
2. 只微调 `maxrefreshsettings` 与 `defaultMaxRate`；
3. 保留所有 OEM 应用、场景、VRR 与 ADFR 策略；
4. 在模块 `system.prop` 中声明 `ro.oplus.refreshrate.maxsettings=4`，让
   ColorOS 设置的“自定义应用刷新率”保留原生 144Hz / ID 4 选项；
5. 写入前验证，卸载时恢复备份。

不要在仓库里放一份手写的完整 XML 覆盖所有系统规则。ROM 更新后，原厂 XML
可能变化，始终应以设备当前文件为基线。

这里的属性不会凭空制造 144Hz。设置程序会先从 DisplayManager 读取真实模式，
再用该属性决定应用刷新率菜单的最高原生 ID；只有 DRM、Android 显示缓存和
ColorOS 配置均已识别 ID 4 时，它才应设为 `4`。详细分析见
[companion/README_CN.md](companion/README_CN.md)。

## ABI、KCFI 与 CRC

### vermagic

源码中的 `PLF110_VERMAGIC` 必须与目标设备完整 `uname -r` 匹配。不同后缀、
抢占配置或 modversions 状态都可能导致 `Invalid module format`。

### 符号 CRC

文件底部的 `__versions` 来自已验证内核的符号版本。更换内核后必须重新取得
对应 `Module.symvers`/CRC，不能复制旧值。CRC 一致也不能证明厂商私有结构体
布局一致。

### KCFI

本实现会在改写 callback 前读取函数入口前的 KCFI type ID，确认原回调与包装
函数原型一致。必须使用匹配的 Clang、头文件、feature 宏和函数签名编译；否则
间接调用可能直接触发 CFI failure。

### 厂商结构体

`struct mtk_dsi`、`struct mtk_panel_params`、`struct mtk_panel_funcs` 都不是稳定
内核 ABI。字段偏移错误通常不会在 C 编译阶段报错，而会在加载或切档时造成
内核崩溃，所以不能把本模块直接用于其他机型或其他分支。

## 验证清单

- 正向与反向切换：60/90/120/144。
- 智能档位与游戏指定 144Hz。
- 低亮度静置、亮灭屏、AOD、自动亮度。
- 指纹解锁、局部 HBM 和高亮度模式。
- 小窗、横竖屏、视频播放和游戏切后台。
- 挂起/恢复、充电、温度升高后的系统策略。
- dmesg 中无 DSI timeout、underflow、KCFI failure 或 mode validation failure。

出现二屏、严重发绿、闪屏、黑屏或重启时应立即禁用模块，从 KernelSU/Magisk
安全模式删除启动模块，并保留 pstore、dmesg 与模块 `status/modes` 信息。

## 已知边界

- 只支持 PLF110 AA600 VDO 面板的已验证 ABI。
- 144Hz DDIC 路径仍是原厂 120Hz 命令路径；这是有意的风险控制设计。
- 本仓库不保证第三方内核兼容，也不根据内核版本字符串猜测兼容性。
- 用户空间显示的档位数字不是示波器级硬件证明。
- 运行时钩子安装后模块会自持引用，本次开机不能直接热卸载；禁用/卸载后重启
  才是可靠恢复方式。
