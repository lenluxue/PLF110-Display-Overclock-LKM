#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# Build the read-only ColorOS policy helper; do not execute it on the device.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
out=${PLF110_POLICY_OUTPUT_DIR:-$root/out/policy}
javac=${PLF110_JAVAC:-javac}
d8=${PLF110_D8:-d8}
mkdir -p "$out/classes" "$out/dex"
"$javac" --release 8 -d "$out/classes" "$root/src/Plf110PolicyReader.java"
"$d8" --min-api 26 --output "$out/dex" "$out/classes/Plf110PolicyReader.class"
cp "$out/dex/classes.dex" "$out/plf110-policy-reader.dex"
echo "policy helper: $out/plf110-policy-reader.dex"
sha256sum "$out/plf110-policy-reader.dex"
