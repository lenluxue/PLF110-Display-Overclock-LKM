# Stable-280 实现说明

以维护者提供的正式 `PLF110-144-v1.12.1-Stable-280.zip` 为准。
144Hz 链路 1399Mbps、像素时钟 464486kHz 及原厂模式/指纹兼容沿用原实现；
本次更新亮度扩展与对应 worker，不改应用策略、挂载或 HWC 流程。
基础模式与时序见 [278 KO 说明](Stable-278-KO.md)，启动流程见 [280 配套流程](Stable-280-Module.md)。

## 正常背光单次补偿

279 的切档补偿已排在同一 CMDQ 的 PHY 更新前，但切档之后的普通背光请求仍可能
恢复原值，再被用户态周期补写。固定刷新率下也可能出现短时亮回。

280 的 `src/brightness_sync.c` 保留切档同步，并添加可选 `mtk_dsi_io_cmd` 钩子：

1. 只处理主 DSI、`DSI_SET_BL=38`、有效 handle/params 和自定义144路径。
2. 以本次实际原始背光 scalar 为输入，在原厂发送前算一次目标值；不依赖旧 control request。
3. 保留原请求和指针，用局部目标值、同一 CMDQ handle 调用原厂路径一次。
4. 切档过程中按同一 task 的目的档位判断；日常路径按 `data_rate=1399` / hopping 状态判断。
5. 自身切档目标以精确 params 指针/task 跳过；原函数递归以 ARM64 原调用返回 LR 标记跳过，避免重复衰减且不屏蔽其他线程。

不是每5ms强制抢写背光。trap handler 仅重定向PC，不分配、不睡眠、不直接发送背光。
保留原厂 OFP/HBM/指纹、guard、vdo_mix 保护；0/1及超出普通亮度范围的请求直通。
不改 AOD、RECOVERY、ELVSS 等其他命令。

## Worker 与回退

`src/brightness_comp.c` 仍每20ms维护请求/所有权、每秒热读配置：
- `live=1` 时，热调或必要补写送原始 request，由 KO 单次补偿，不能送已缩放值。
- 启用同步后立即回读 live 能力，避免首次请求被二次缩放。
- sync 已开但能力未知时暂不写；可选钩子不支持时沿用279切档同步与用户态回退。
- 停止或禁用时先注销同步，再按既有所有权规则恢复；原厂档位、保护场景不强制补偿。

默认 `brightness_gain.conf=93`、`brightness_sync.conf=1`。
增益范围70.0–100.0%、0.1%精度，100为不衰减；用整数定点计算，不用内核浮点。

## ABI、构建与状态

可选钩子核对主DSI回调地址、地址稳定性及厂商CFI签名；缺失或不匹配时回退，
不因新增功能阻止旧同步启动。直接字段偏移沿用已验证原KO布局，不是通用ABI。
基础实现兼容基线不等于新增钩子已在全部系统/内核实测。

构建环境与命令沿用 [279构建说明](Stable-279.md#构建) 和 [ABI参考](Reference-build_CN.md)：
运行 `scripts/build_brightness.sh`，输入必须是原正式278 KO，SHA256
`67bd63e0b1583a96c9ccefbf1f8ebd5ddc2312c2fae56f019b8eed833b30fd82`。
不是把279 KO重复追加扩展。链接脚本保留原代码、时序、21导入/CRC和模块入口，
重绑原12个回调地址重定位；核对新入口CFI及BLR/LR标记，不全局关闭CFI。
`check_module.sh` 增加 live 入口及能力检查；构建不会自动加载KO。

`brightness_sync_status` 新增 `live`、`live_seen`、`live_fixed`、`live_skipped`、
`live_error`、`live_input=raw`。`queued` 含新增普通背光事件，不能视为物理亮度测量。
安装后需手动重启加载新KO，单重载HWC不能换KO。验证先看 `live=1` / `live_error=0`
及普通背光请求时 `live_fixed` 增长，再复现游戏、自动亮度及指纹/HBM。

## 产物与验证边界

| 文件 | 字节 | SHA-256 |
| --- | ---: | --- |
| Stable-280 ZIP | 119048 | `ef31baee1be9dd6af138ff7cff89987e8b9104a8123727fa2eaa6a074c3098af` |
| KO | 76000 | `dcc84c8029261668254515ebe85a57aedfb23dd56230ed91994bf0b18c6e1ce0` |
| worker | 17000 | `ef447633df4831289045c8d6cfa514c14303e0920f171db7930508640c90a88d` |

此前测试通过1061810原同步及1232896 live gain/DBV案例、1000重复请求，
另在隔离假sysfs验证3514连续原厂请求、热调/未知能力/回退/停止恢复。
本次正式包完整性、Android Shell语法及与测试包的内容对比通过；维护者微调仅版本信息。
本次以仓库构建入口重建的KO与发行包逐字节一致；worker源码编译通过，代码段/只读数据与发行worker一致。
这些是静态、模拟及隔离用户态测试，不能代替新KO实机CMDQ/光学验证，
不保证所有亮度/HDR/指纹/ROM场景消除闪亮。完整安装包只放发行版，不上传工程或私钥。
