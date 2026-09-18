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
		bus_find_device|copy_from_kernel_nofault|\
		drm_kms_helper_hotplug_event|drm_mode_duplicate|\
		drm_mode_probed_add|drm_mode_set_name|memcpy|module_put|\
		mutex_lock|mutex_unlock|platform_bus_type|put_device|\
		register_kprobe|scnprintf|strcmp|try_module_get|\
		unregister_kprobe)
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

grep -Fq '#define PLF110_144_DATA_RATE 1395' \
	"$project_root/src/PLF110_144_Mode.c" || \
	fail "source no longer declares the validated 1395 Mbps link"
grep -Fq 'mode_matches(mode, 464486, 1080, 1209, 1213, 1229,' \
	"$project_root/src/PLF110_144_Mode.c" || \
	fail "source no longer declares the validated 144 Hz timing"

echo "module:   $module"
echo "sha256:  $(sha256sum "$module" | awk '{print $1}')"
echo "imports: $(printf '%s\n' "$undefined" | wc -l | tr -d ' ') validated"
echo "result:   static checks passed"
