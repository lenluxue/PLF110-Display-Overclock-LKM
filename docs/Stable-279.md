# Stable-279

> 历史版本说明；当前实现见 [Stable-280](Stable-280.md) 与 [配套流程](Stable-280-Module.md)。

基于维护者提供的正式 279 安装包。144Hz 时序与 1399Mbps 链路沿用 278，
新增亮度扩展；安装提示保留维护者微调。完整安装包仅见发行版。

## 亮度同步

- 默认 `brightness_gain.conf=93`，范围 70.0–100.0%，步进 0.1%；100 关闭补偿。
- `brightness_sync.conf=1`；service 在系统启动完成及 HWC 流程之后启动 worker。
- `src/brightness_sync.c` 把切档背光补偿排进同一 CMDQ，在原 PHY 时序更新前执行。
- `src/brightness_comp.c` 每 20ms 维护原始亮度请求，热读配置并处理回退、退出恢复。
- `src/brightness_gain.h` 使用整数定点百分比；86.5% 表示为 865，
  输出 DBV 为 `(request * 865 + 500) / 1000`，不使用内核浮点。
- 保留原厂 OFP/HBM 过滤、高亮与指纹避让；参数默认关闭同步且保持 guard。

该系数来自本机观感调校，不等于光学标定。亮度边界、HDR、指纹和其他 ROM
仍需实机验证；不保证所有场景完全消除亮度差或闪光。

## 构建

基础实现与 ABI 输入见 [构建参考](Reference-build_CN.md)。基础源码不是逐字节
复现发行 KO 的保证；279 扩展构建严格接受原正式 278 的已验证 KO，不接收任意重编译产物。
需要 Clang 21.1.8、llvm-objcopy、ld.lld、Python 3 和 pyelftools。

```sh
export PLF110_HEADERS_DIR=/path/to/generated-headers
export PLF110_DISPLAY_ROOT=/path/to/kernel/kernel_device_modules-6.1
export PLF110_CLANG=/path/to/clang
export PLF110_LD_LLD=/path/to/ld.lld
export PLF110_OBJCOPY=/path/to/llvm-objcopy
export PLF110_BASE_KO=/path/to/original-Stable-278/PLF110_Display_OC.ko
sh scripts/build_brightness.sh
```

输出 `out/brightness/PLF110_Display_OC.ko`，不会自动加载。
链接脚本保留原代码、时序、导入/CRC，仅追加扩展并重绑 12 个回调地址重定位；
输入 KO SHA-256 固定为 `67bd63e0b1583a96c9ccefbf1f8ebd5ddc2312c2fae56f019b8eed833b30fd82`。

worker 可用 Android NDK 的 AArch64/Bionic Clang 编译：

```sh
/path/to/aarch64-linux-android30-clang -O2 -Wall -Wextra -Werror \
  src/brightness_comp.c -o /path/to/plf110-brightness-comp
```

需核对 ELF 使用 `/system/bin/linker64`、系统 Bionic 依赖，且不携带 Termux 私有
RPATH/RUNPATH。源码中的单元测试分支不进入生产构建，测试资料不进入安装包。
279 沿用 [278 配套流程](Stable-278-Module.md)，并增加上述亮度 worker 和两份配置；
本次未改写其余挂载、HWC、应用分档和日志清理逻辑。

## 发行校验

| 文件 | SHA-256 |
| --- | --- |
| Stable-279 ZIP | `3d4c7e34440979fbce529f330ed7df8e617b964f711e2272f074b1976c3ff3c0` |
| KO | `20390433055ead0c62b521bf5f88f014da1a7dbe3174b2cf0f457ca64a4f84ce` |
| worker | `a912a69192d0dc9edc285286feea8c5090cef20392da45b2686ca93fc290b10a` |

初次发布时仅修复 ZIP 目录条目重叠元数据，未改文件内容；本次仅调整默认系数，KO 仍为 67360 字节。
ZIP 完整性和 Android Shell 语法通过；静态检查不能替代新包的实机测试。

默认系数按维护者实测从 86.5% 调整为 93%，覆盖同名 279 资产；KO、worker 和其他文件不变。
版本号与 versionCode 仍为 279，已安装 279 的用户需重新下载刷入，不会收到更高版本号的自动更新提示。
