#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
r=${PLF110_OUTPUT_DIR:-$project_root/out/brightness}
s=$project_root/src
h=${PLF110_HEADERS_DIR:?Set PLF110_HEADERS_DIR to complete generated kernel headers}
d=${PLF110_DISPLAY_ROOT:?Set PLF110_DISPLAY_ROOT to matching kernel_device_modules-6.1}
clang=${PLF110_CLANG:?Set PLF110_CLANG to validated Clang 21.1.8}
base=${PLF110_BASE_KO:?Set PLF110_BASE_KO to the unmodified Stable-278 KO}
case "$("$clang" --version | sed -n '1p')" in
 *"clang version 21.1.8"*) ;;
 *) echo "error: this extension requires validated Clang 21.1.8" >&2; exit 1 ;;
esac
mkdir -p "$r"
"$clang" --target=aarch64-linux-gnu -std=gnu11 -O2 \
 -D__KERNEL__ -DMODULE -DCONFIG_MTK_CMDQ_MBOX_EXT=1 \
 '-DKBUILD_MODNAME="PLF110_Display_OC"' '-DKBUILD_BASENAME="brightness_sync"' \
 -include "$h/include/linux/compiler-version.h" -include "$h/include/linux/kconfig.h" \
 -I"$h/arch/arm64/include" -I"$h/arch/arm64/include/generated" -I"$h/include" \
 -I"$h/arch/arm64/include/uapi" -I"$h/arch/arm64/include/generated/uapi" \
 -I"$h/include/uapi" -I"$h/include/generated/uapi" \
 -I"$d/drivers/gpu/drm/mediatek/mediatek_v2" -I"$d/drivers/misc/mediatek/mtk-interconnect" \
 -I"$d/include" -I"$d/drivers/misc/mediatek/cmdq/mailbox" -I"$d/drivers/misc/mediatek/include/mt-plat" \
 -Wall -Wextra -Werror -Wno-unused-parameter -Wno-pointer-sign -Wno-sign-compare \
 -Wno-gnu-variable-sized-type-not-at-end -fno-pic -fno-PIE -fno-common -fno-builtin \
 -fno-stack-protector -fno-asynchronous-unwind-tables -fno-unwind-tables \
 -fno-delete-null-pointer-checks -fno-strict-overflow -fno-optimize-sibling-calls \
 -fno-omit-frame-pointer -ffixed-x18 -fsanitize=kcfi \
 -fsanitize-cfi-icall-experimental-normalize-integers -mbranch-protection=pac-ret \
 -mgeneral-regs-only -mstrict-align -mno-outline-atomics -mcmodel=large \
 -ffunction-sections -fdata-sections -c "$s/brightness_sync.c" -o "$r/brightness_sync.o"
python3 "$project_root/scripts/link_brightness.py" "$base" "$r/brightness_sync.o" "$r/PLF110_Display_OC.ko"
sh "$project_root/scripts/check_module.sh" "$r/PLF110_Display_OC.ko"
