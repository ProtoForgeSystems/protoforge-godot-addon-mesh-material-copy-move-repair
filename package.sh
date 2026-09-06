#!/usr/bin/env bash
# Build the asset-store ZIP: tracked files wrapped under addons/sidecar/,
# minus repo metadata the store guidelines prohibit and the test suite.
set -euo pipefail
cd "$(dirname "$0")"
rm -rf build
mkdir -p build/addons/sidecar
# Godot still scans res:// even though git ignores build/ -- without this,
# staging a copy of every script here trips the editor's UID-duplicate
# detector against the originals.
touch build/.gdignore
git ls-files | grep -v -e '^\.git' -e '^package\.sh$' -e '^tests/' -e '^run_tests\.sh$' | while read -r f; do
    mkdir -p "build/addons/sidecar/$(dirname "$f")"
    cp "$f" "build/addons/sidecar/$f"
done
(cd build && zip -qr sidecar.zip addons)
echo "build/sidecar.zip:"
unzip -l build/sidecar.zip
