#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only

set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
module=${1:-$project_root/out/PLF110_144_Mode.ko}
readelf=${LLVM_READELF:-llvm-readelf}
nm=${LLVM_NM:-llvm-nm}
objdump=${LLVM_OBJDUMP:-llvm-objdump}

fail() {
	echo "error: $*" >&2
	exit 1
}

[ -f "$module" ] || fail "module not found: $module"
command -v "$readelf" >/dev/null 2>&1 || fail "missing tool: $readelf"
command -v "$nm" >/dev/null 2>&1 || fail "missing tool: $nm"
command -v "$objdump" >/dev/null 2>&1 || fail "missing tool: $objdump"

elf_header=$("$readelf" -h "$module")
modinfo=$("$readelf" -p .modinfo "$module")
sections=$("$readelf" -SW "$module")
versions=$("$readelf" -p __versions "$module")
undefined=$("$nm" -u "$module" | awk '{print $2}' | sort -u)

printf '%s\n' "$elf_header" | grep -q 'Type:.*REL' || \
	fail "module is not an ELF relocatable object"
printf '%s\n' "$elf_header" | grep -q 'Machine:.*AArch64' || \
	fail "module is not AArch64"
printf '%s\n' "$sections" | grep -q '__versions' || \
	fail "missing __versions section"
printf '%s\n' "$sections" | grep -q '\.gnu\.linkonce\.this_module' || \
	fail "missing __this_module section"

printf '%s\n' "$modinfo" | grep -q 'license=GPL' || \
	fail "missing GPL module license"
printf '%s\n' "$modinfo" | grep -q 'name=PLF110_Display_OC' || \
	fail "unexpected in-kernel module name"
printf '%s\n' "$modinfo" | grep -q \
	'vermagic=6.1.157-android14-11-o-gc2dad16af736 SMP preempt mod_unload modversions aarch64' || \
	fail "unexpected vermagic"
grep -aFq '酷安丛雨颜烬 × OpenAI Codex' "$module" || \
	fail "missing author attribution"

for symbol in $undefined; do
	case "$symbol" in
		__list_add_valid|__list_del_entry_valid|_printk|alt_cb_patch_nops|\
		copy_from_kernel_nofault|\
		drm_kms_helper_hotplug_event|drm_mode_duplicate|\
		drm_mode_probed_add|drm_mode_set_name|memcpy|memset|module_put|\
		mutex_lock|mutex_unlock|\
		register_kprobe|register_kretprobe|scnprintf|strcmp|try_module_get|\
		unregister_kprobe|unregister_kretprobe)
			;;
		*) fail "unexpected undefined symbol: $symbol" ;;
	esac
	printf '%s\n' "$versions" | grep -q " $symbol\$" || \
		fail "missing modversion CRC for: $symbol"
done

printf '%s\n' "$versions" | grep -q ' module_layout$' || \
	fail "missing module_layout CRC"
"$objdump" -d "$module" | grep -q 'brk.*#0x82' || \
	fail "no KCFI trap sequence found"
"$objdump" -d "$module" | grep -q '[[:space:]]blr[[:space:]]' || \
	fail "no indirect callback call found"
# The target kernel's module entry/exit trampolines use these CFI type IDs.
# A clang-produced module with different IDs panics in do_one_initcall before
# the module body runs, so reject it before it can be packaged or loaded.
init_text=$($objdump -d -j .init.text "$module" 2>/dev/null | sed -n 's/^[[:space:]]*0:.*\.word[[:space:]]*0x\([0-9a-fA-F]*\).*/\1/p' | head -n 1)
exit_text=$($objdump -d -j .exit.text "$module" 2>/dev/null | sed -n 's/^[[:space:]]*0:.*\.word[[:space:]]*0x\([0-9a-fA-F]*\).*/\1/p' | head -n 1)
[ "$init_text" = "36b1c5a6" ] || fail "unexpected init_module KCFI type: ${init_text:-missing}"
[ "$exit_text" = "a540670c" ] || fail "unexpected cleanup_module KCFI type: ${exit_text:-missing}"

check_symbol_cfi() {
	symbol=$1
	expected=$2
	actual=$($objdump -d "$module" |
		awk -v wanted="<$symbol>:" '
			$0 ~ wanted { print previous; exit }
			$0 !~ /^[[:space:]]*$/ { previous = $0 }
		' |
		sed -n 's/.*\.word[[:space:]]*0x\([0-9a-fA-F]*\).*/\1/p')
	[ "$actual" = "$expected" ] ||
		fail "unexpected $symbol KCFI type: ${actual:-missing} (expected $expected)"
}

for symbol in enable_set refresh_set; do
	check_symbol_cfi "$symbol" 63fa7f9c
done
for symbol in enable_get status_get modes_get; do
	check_symbol_cfi "$symbol" c64c3dfc
done
check_symbol_cfi plf110_panel_get_modes 4ccb5d06
check_symbol_cfi plf110_connector_fill_modes 9fc1a63b
check_symbol_cfi plf110_mode_switch_update_for_vdo 9fc1a63b
check_symbol_cfi plf110_ext_param_set 3cf3199f
check_symbol_cfi plf110_ext_param_get f7ea43f0
check_symbol_cfi panel_pre_handler a6be5dd9
check_symbol_cfi porch_pre_handler a6be5dd9
for symbol in plf110_enum_entry plf110_enum_ret ofp_entry ofp_ret vref_ret; do
	check_symbol_cfi "$symbol" 8078be15
done

# DSI io_cmd indirect calls must use the vendor callback type carried by the
# known-good 144 Hz module. Reject the incompatible standalone compiler ID.
if "$objdump" -d "$module" | grep -q '72924ed1.*movk.*#0x9276'; then
	fail "incompatible DSI io_cmd call-site KCFI type remains"
fi
printf '%s\n' "$($objdump -d "$module")" | grep -q '728a7631.*movk.*#0x53b1' ||
	fail "missing normalized DSI io_cmd call-site KCFI type"
printf '%s\n' "$($objdump -d "$module")" | grep -q '72bf4451.*movk.*#0xfa22' ||
	fail "missing normalized DSI io_cmd high KCFI word"
for incompatible in \
	'728ff5d1.*#0x7fae' '72a94911.*#0x4a48' \
	'7295dc11.*#0xaee0' '72a98d31.*#0x4c69' \
	'729d0291.*#0xe814' '72a010f1.*#0x87' \
	'72988dd1.*#0xc46e' '72a28fb1.*#0x147d'; do
	if "$objdump" -d "$module" | grep -q "$incompatible"; then
		fail "incompatible vendor callback call-site KCFI type remains: $incompatible"
	fi
done
for normalized in \
	'728333f1.*#0x199f' '72a79e71.*#0x3cf3' \
	'72887e11.*#0x43f0' '72befd51.*#0xf7ea' \
	'728ba0d1.*#0x5d06' '72a99971.*#0x4ccb' \
	'7294c771.*#0xa63b' '72b3f831.*#0x9fc1'; do
	printf '%s\n' "$($objdump -d "$module")" | grep -q "$normalized" ||
		fail "missing normalized vendor callback call-site KCFI type: $normalized"
done

grep -Fq '#define PLF110_144_DATA_RATE 1395' \
	"$project_root/src/PLF110_144_Mode.c" || \
	fail "source no longer declares the validated 1395 Mbps link"
grep -Fq 'state.custom_ext.dyn_fps.vact_timing_fps = 120;' \
	"$project_root/src/PLF110_144_Mode.c" || \
	fail "144 panel profile no longer stays on the stock 120 Hz policy"
grep -Fq 'mode_matches(mode, 464486, 1080, 1209, 1213, 1229,' \
	"$project_root/src/PLF110_144_Mode.c" || \
	fail "source no longer declares the validated 144 Hz timing"

echo "module:   $module"
echo "sha256:  $(sha256sum "$module" | awk '{print $1}')"
echo "imports: $(printf '%s\n' "$undefined" | wc -l | tr -d ' ') validated"
echo "result:   static checks passed"
