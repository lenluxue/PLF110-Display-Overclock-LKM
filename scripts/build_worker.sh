#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# Reproduce the validated Android/Bionic worker in Termux; never run it here.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
prefix=${PLF110_ANDROID_PREFIX:-/data/data/com.termux/files/usr}
clang=${PLF110_WORKER_CLANG:-clang}
ld=${PLF110_LD_LLD:-ld.lld}
strip=${PLF110_STRIP:-llvm-strip}
out=${PLF110_WORKER_OUTPUT_DIR:-$root/out/brightness}
case "$("$clang" --version | sed -n '1p')" in
 *"clang version 21.1.8"*) ;;
 *) echo "error: use validated Android Clang 21.1.8" >&2; exit 1 ;;
esac
mkdir -p "$out"
"$clang" -O2 -Wall -Wextra -Werror -ffunction-sections -fdata-sections  -c "$root/src/brightness_comp.c" -o "$out/brightness_comp.o"
"$ld" --sysroot="$prefix/.." -EL --fix-cortex-a53-843419 -z now -z relro  -z max-page-size=16384 --no-rosegment --hash-style=gnu --eh-frame-hdr  -m aarch64linux -pie -dynamic-linker /system/bin/linker64 --gc-sections  -o "$out/plf110-brightness-comp" "$prefix/lib/crtbegin_dynamic.o"  -L"$prefix/lib" -L/system/lib64 "$out/brightness_comp.o"  "$prefix/lib/clang/21/lib/linux/libclang_rt.builtins-aarch64-android.a"  -l:libunwind.a -ldl -lc  "$prefix/lib/clang/21/lib/linux/libclang_rt.builtins-aarch64-android.a"  -l:libunwind.a -ldl "$prefix/lib/crtend_android.o"
"$strip" --strip-unneeded "$out/plf110-brightness-comp"
echo "worker: $out/plf110-brightness-comp"
sha256sum "$out/plf110-brightness-comp"
