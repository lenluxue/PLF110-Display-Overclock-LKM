#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only

set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
module_dir=${PLF110_MODULE_DIR:-$project_root/module}
output_dir=${PLF110_PACKAGE_OUTPUT_DIR:-$project_root/out}
package_name=${PLF110_PACKAGE_NAME:-PLF110-144-v1.12.1-Stable.zip}

case "$module_dir" in
	/*) ;;
	*) module_dir=$project_root/$module_dir ;;
esac
case "$output_dir" in
	/*) ;;
	*) output_dir=$project_root/$output_dir ;;
esac

fail() {
	echo "error: $*" >&2
	exit 1
}

command -v zip >/dev/null 2>&1 || fail "missing tool: zip"
[ -d "$module_dir" ] || fail "module directory not found: $module_dir"
[ -f "$module_dir/module.prop" ] || fail "missing module.prop"
[ -f "$module_dir/customize.sh" ] || fail "missing customize.sh"
[ -f "$module_dir/PLF110_Display_OC.ko" ] || fail "missing release LKM"

# Prefer a freshly validated build, while retaining the exact tested release
# binary when an old or incompatible build is left in out/.
explicit_ko=${PLF110_KO:-}
if [ -n "$explicit_ko" ]; then
	module_ko=$explicit_ko
	[ -f "$module_ko" ] || fail "requested LKM not found: $module_ko"
elif [ -f "$output_dir/PLF110_144_Mode.ko" ] &&
	[ "${PLF110_SKIP_CHECK:-0}" = 1 ]; then
	module_ko=$output_dir/PLF110_144_Mode.ko
elif [ -f "$output_dir/PLF110_144_Mode.ko" ] &&
	"$project_root/scripts/check_module.sh" "$output_dir/PLF110_144_Mode.ko" >/dev/null 2>&1; then
	module_ko=$output_dir/PLF110_144_Mode.ko
else
	module_ko=$module_dir/PLF110_Display_OC.ko
	echo "notice: using checked-in tested LKM; no validated fresh build was found" >&2
fi

if [ "${PLF110_SKIP_CHECK:-0}" != 1 ]; then
	"$project_root/scripts/check_module.sh" "$module_ko"
fi

mkdir -p "$output_dir"
stage=$(mktemp -d "${TMPDIR:-/tmp}/plf110-module.XXXXXX")
cleanup() {
	rm -rf "$stage"
}
trap cleanup EXIT HUP INT TERM

cp -a "$module_dir/." "$stage/"
cp -f "$module_ko" "$stage/PLF110_Display_OC.ko"
chmod 0644 "$stage/PLF110_Display_OC.ko"

package_path=$output_dir/$package_name
rm -f "$package_path"
(CDPATH= cd "$stage" && zip -qr -X "$package_path" .)

echo "module:  $module_ko"
echo "package: $package_path"
echo "sha256:  $(sha256sum "$package_path" | awk '{print $1}')"
