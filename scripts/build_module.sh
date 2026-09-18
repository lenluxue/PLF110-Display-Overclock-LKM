#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only

set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
headers_dir=${PLF110_HEADERS_DIR:-}
kernel_source=${PLF110_KERNEL_SOURCE:-}
display_root=${PLF110_DISPLAY_ROOT:-}
clang=${PLF110_CLANG:-}
linker=${PLF110_LD_LLD:-}
module_name=${PLF110_MODULE_NAME:-PLF110_Display_OC}
output_dir=${PLF110_OUTPUT_DIR:-$project_root/out}
source_file=$project_root/src/PLF110_144_Mode.c

fail() {
	echo "error: $*" >&2
	exit 1
}

[ -n "$headers_dir" ] || fail "PLF110_HEADERS_DIR is required"
[ -n "$kernel_source" ] || fail "PLF110_KERNEL_SOURCE is required"
[ -n "$display_root" ] || fail "PLF110_DISPLAY_ROOT is required"
[ -n "$clang" ] || fail "PLF110_CLANG is required"
[ -n "$linker" ] || fail "PLF110_LD_LLD is required"
[ -f "$source_file" ] || fail "missing source: $source_file"
[ -f "$headers_dir/include/linux/compiler-version.h" ] || \
	fail "incomplete generated kernel headers: $headers_dir"
[ -f "$headers_dir/include/linux/kconfig.h" ] || \
	fail "incomplete generated kernel headers: $headers_dir"
[ -f "$kernel_source/scripts/module.lds.S" ] || \
	fail "missing module linker script below: $kernel_source"
[ -f "$display_root/drivers/gpu/drm/mediatek/mediatek_v2/mtk_dsi.h" ] || \
	fail "missing MTK DSI ABI headers below: $display_root"
[ -x "$clang" ] || fail "clang is not executable: $clang"
[ -x "$linker" ] || fail "ld.lld is not executable: $linker"

compiler_version=$("$clang" --version | sed -n '1p')
case "$compiler_version" in
	*"clang version 21.1.8"*) ;;
	*) fail "unexpected compiler: $compiler_version (validated build uses Clang 21.1.8)" ;;
esac

display_driver=$display_root/drivers/gpu/drm/mediatek/mediatek_v2
display_include=$display_root/include
interconnect_dir=$display_root/drivers/misc/mediatek/mtk-interconnect
cmdq_dir=$display_root/drivers/misc/mediatek/cmdq/mailbox
mtk_platform_include=$display_root/drivers/misc/mediatek/include/mt-plat
mkdir -p "$output_dir"

"$clang" \
	--target=aarch64-linux-gnu \
	-E -P -x assembler-with-cpp \
	-D__KERNEL__ -D__ASSEMBLY__ \
	-include "$headers_dir/include/linux/compiler-version.h" \
	-include "$headers_dir/include/linux/kconfig.h" \
	-I"$headers_dir/arch/arm64/include" \
	-I"$headers_dir/arch/arm64/include/generated" \
	-I"$headers_dir/include" \
	-I"$headers_dir/arch/arm64/include/uapi" \
	-I"$headers_dir/arch/arm64/include/generated/uapi" \
	-I"$headers_dir/include/uapi" \
	-I"$headers_dir/include/generated/uapi" \
	"$kernel_source/scripts/module.lds.S" \
	-o "$output_dir/module.lds"

"$clang" \
	--target=aarch64-linux-gnu \
	-std=gnu11 -O2 \
	-D__KERNEL__ -DMODULE \
	-DCONFIG_MTK_CMDQ_MBOX_EXT=1 \
	-"DKBUILD_MODNAME=\"$module_name\"" \
	-"DKBUILD_BASENAME=\"$module_name\"" \
	-include "$headers_dir/include/linux/compiler-version.h" \
	-include "$headers_dir/include/linux/kconfig.h" \
	-I"$headers_dir/arch/arm64/include" \
	-I"$headers_dir/arch/arm64/include/generated" \
	-I"$headers_dir/include" \
	-I"$headers_dir/arch/arm64/include/uapi" \
	-I"$headers_dir/arch/arm64/include/generated/uapi" \
	-I"$headers_dir/include/uapi" \
	-I"$headers_dir/include/generated/uapi" \
	-I"$display_driver" \
	-I"$interconnect_dir" \
	-I"$display_include" \
	-I"$cmdq_dir" \
	-I"$mtk_platform_include" \
	-Wall -Wextra -Werror \
	-Wno-unused-parameter \
	-Wno-pointer-sign \
	-Wno-sign-compare \
	-Wno-gnu-variable-sized-type-not-at-end \
	-fno-pic -fno-PIE -fno-common -fno-builtin \
	-fno-stack-protector -fno-asynchronous-unwind-tables \
	-fno-unwind-tables -fno-delete-null-pointer-checks \
	-fno-strict-overflow -fno-optimize-sibling-calls \
	-fno-omit-frame-pointer -ffixed-x18 \
	-fsanitize=kcfi \
	-fsanitize-cfi-icall-experimental-normalize-integers \
	-mbranch-protection=pac-ret -mgeneral-regs-only -mstrict-align \
	-mno-outline-atomics -mcmodel=large \
	-c "$source_file" \
	-o "$output_dir/$module_name.o"

"$linker" \
	-r -m aarch64elf -z noexecstack --build-id=sha1 \
	-T "$output_dir/module.lds" \
	-o "$output_dir/PLF110_144_Mode.ko" \
	"$output_dir/$module_name.o"

echo "compiler: $compiler_version"
echo "source:   $source_file"
echo "output:   $output_dir/PLF110_144_Mode.ko"
