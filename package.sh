#!/usr/bin/env bash
# Build the asset-store ZIP: tracked files wrapped under addons/mesh_material_copy_move_repair/,
# minus repo metadata the store guidelines prohibit and the test suite.
set -euo pipefail
cd "$(dirname "$0")"
rm -rf build
mkdir -p build/addons/mesh_material_copy_move_repair
# Godot still scans res:// even though git ignores build/ -- without this,
# staging a copy of every script here trips the editor's UID-duplicate
# detector against the originals.
touch build/.gdignore
git ls-files | grep -v -e '^\.git' -e '^package\.sh$' -e '^tests/' -e '^run_tests\.sh$' | while read -r f; do
    mkdir -p "build/addons/mesh_material_copy_move_repair/$(dirname "$f")"
    cp "$f" "build/addons/mesh_material_copy_move_repair/$f"
done
(cd build && zip -qr mesh_material_copy_move_repair.zip addons)
echo "build/mesh_material_copy_move_repair.zip:"
unzip -l build/mesh_material_copy_move_repair.zip
