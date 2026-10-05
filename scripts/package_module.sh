#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# Assemble the flashable KernelSU/Magisk module from module/ plus the LKM
# produced by build_module.sh. Keeping this in the repository makes the
# released ZIP reproducible instead of hand-assembled.

set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
module_dir=$project_root/module
kernel_module=${PLF110_KO:-$project_root/out/PLF110_144_Mode.ko}
output_zip=${PLF110_ZIP:-$project_root/out/PLF110-144-v1.12.1-Beta-266.zip}

fail() {
	echo "error: $*" >&2
	exit 1
}

[ -d "$module_dir" ] || fail "missing module directory: $module_dir"
[ -f "$kernel_module" ] || fail "missing LKM (run build_module.sh first): $kernel_module"
command -v zip >/dev/null 2>&1 || fail "missing tool: zip"

version=$(sed -n 's/^version=//p' "$module_dir/module.prop" | head -n 1)
version_code=$(sed -n 's/^versionCode=//p' "$module_dir/module.prop" | head -n 1)
[ -n "$version" ] || fail "module.prop has no version"
[ -n "$version_code" ] || fail "module.prop has no versionCode"

stage=$(mktemp -d "${TMPDIR:-/tmp}/plf110-module.XXXXXX")
trap 'rm -rf "$stage"' EXIT

cp -a "$module_dir/." "$stage/"
cp -f "$kernel_module" "$stage/PLF110_Display_OC.ko"
chmod 0755 "$stage"/*.sh
chmod 0644 "$stage/module.prop" "$stage/system.prop"
chmod 0644 "$stage/PLF110_Display_OC.ko"

mkdir -p "$(dirname -- "$output_zip")"
rm -f "$output_zip"
(cd "$stage" && zip -r -9 -X "$output_zip" . >/dev/null)

echo "module:  $kernel_module"
echo "version: $version ($version_code)"
echo "output:  $output_zip"
