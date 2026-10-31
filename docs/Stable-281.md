# Stable-281 实现说明

正式包：`PLF110-144-v1.12.2-Stable-281.zip`，以维护者微调后的原包为准。
沿用 1399Mbps 链路、464486kHz 像素时钟、原厂模式和指纹路径；不改应用策略或 HWC 流程。
基础时序见 [278 KO 说明](Stable-278-KO.md)，启动流程见 [281 配套流程](Stable-281-Module.md)。

## 亮度补偿思路

> 当超频出现亮度不同时可以参考

保留 [280 的正常背光单次补偿](Stable-280.md#正常背光单次补偿)：
只处理主 DSI 的普通 `DSI_SET_BL` 请求，在原厂发送前以本次 raw DBV 计算一次目标值；
切档时在同一 CMDQ 的 PHY 更新前排入背光。精确 params/task 与 ARM64 LR 标记避免双重衰减。
不猜写面板寄存器，不引入亮灭抖动，保留 HBM/OFP/指纹、guard 和 vdo_mix 保护。

固定百分比无法覆盖整条亮度滑条，所以281使用共享整数曲线：
`src/brightness_gain.h` 同时用于 KO 和 worker；基础增益与曲线参数分开配置。

```text
brightness_gain.conf = 92
brightness_sync.conf = 1
brightness_curve.conf = 1:2664:88.4:93:98.5:1:2.0
```

七个字段依次为 `ENABLE:PIVOT_DBV:LOW_PERCENT:MID_PERCENT:HIGH_PERCENT:LOW_EXTRA_DBV:HIGH_EXTRA_PERCENT`。

- 普通请求区间2..3515：曲线在DBV2、2664、3515三个节点线性插值。
  实际增益为 `clamp(base + interpolated - mid, 70%, 100%)`；当前有效节点为87.4/92/97.5%。
- 低尾段：原请求≤4额外减1 DBV，4..64线性衰减至0；正常输出仍不低于2。
- 高尾段：原请求>3072额外衰减从0线性增加至3515处2.0个百分点。
- 原请求64..3072输出与同一core曲线逐值一致；两端统一最后取整，避免额外的非单调台阶。
- 请求0/1、>3515与保护场景直通。基础增益100%关闭衰减；曲线文件写`0`回到固定基础增益。
  低尾段字段只接受0/1，高尾段只接受0..5.0、步进0.1个百分点。

默认软件目标为 raw4→2、raw2664→2451、raw3515→3357；DBV变化不等于光学亮度同比变化。
2664是本机视觉匹配点，不是光学标定。

## 原子配置与回退

全曲线通过一个64位原子字发布；旧五字段兼容，`curve_api=2`才启用两端扩展。
worker每秒热读配置，写入后回读KO实际接受的配置，不使用未经确认的目标参数。
遇到API1仅发送五字段core；未知正数API或无法确认状态时暂停补写。
`live=1`时必要补写发送raw，不发送已缩放target；正常请求不依赖周期性重复补偿。
可选live钩子缺失、地址或CFI不符仍回退旧切档同步与用户态路径。

KO初始曲线关闭，仍由原service在系统完成启动、HWC重载后启动worker并应用配置。
热调配置无需重载HWC；更换KO或worker的安装更新仍需手动重启。

## 构建与校验

```sh
# 设置生成头、显示源码和验证过的工具链，详见279构建说明。
export PLF110_BASE_KO=/path/to/original-Stable-278/PLF110_Display_OC.ko
sh scripts/build_brightness.sh
# 使用验证过的Termux Android/Bionic工具链构建worker，不会执行worker。
sh scripts/build_worker.sh
```

扩展输入必须为未追加亮度扩展的原278 KO，SHA256
`67bd63e0b1583a96c9ccefbf1f8ebd5ddc2312c2fae56f019b8eed833b30fd82`。
不能在279/280/281 KO上重复叠加。保留原代码、时序、模块入口及21导入/CRC，
只追加扩展并重绑原12处回调地址；曲线getter/setter、live入口和原调用LR均核对CFI，未全局关闭CFI。
完整构建条件见 [279构建说明](Stable-279.md#构建) 与 [ABI参考](Reference-build_CN.md)。

| 文件 | 字节 | SHA-256 |
| --- | ---: | --- |
| Stable-281 ZIP | 122961 | `41acfe95d36be4005c8cc1698a55b2c5eab591599a0a03ec225702c5af90d25b` |
| KO | 82192 | `80c4b4b07b0e4babd1a4d12faee097f0a1e79186521fc845a775ee60f2b9abaf` |
| worker | 17424 | `4980cef75a431747794663cba5a88b1f62d7d06acbd1ac33cce24e688587a932` |

## 验证边界

此前已完成整数数学、解析、单调性、中区不变、切档/live保护及假sysfs worker回归。
本次按公开仓库入口重建KO与worker，与281发行文件逐字节一致；ZIP完整性和Android Shell语法通过。
这些检查不等于所有ROM、内核、HDR与指纹场景均已实测。

本机已加载同一两端补偿实现：最低120路径原请求4/软件缓存4，144路径原请求4/软件缓存2，
采样保护均为0。最高端已基本匹配，但最低144仍偏亮，用户选择保留。
软件缓存2不是面板最后DSI命令或光学测量；尚未制作DSI诊断包，也不越过黑位保护继续盲降。
没有保证全亮度范围完全一致。完整模块仅放发行版，工程、源码、测试和凭证不进入安装包。
