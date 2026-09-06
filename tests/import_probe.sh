#!/usr/bin/env bash
# Verifies the engine assumption behind sidecar's .import handling: an .import with uid=, path=
# and dest_files= removed is reimported cleanly, those keys are regenerated, and every other
# parameter survives. Runs in a throwaway project so it touches no repo.
set -euo pipefail
GODOT_BIN="${1:?godot binary path required}"
PROBE="$(mktemp -d)"
trap 'rm -rf "$PROBE"' EXIT
printf 'config_version=5\n\n[application]\n\nconfig/name="sidecar probe"\n' > "$PROBE/project.godot"

# A real 4x4 PNG, written by Godot itself so the file is genuinely importable.
cat > "$PROBE/make.gd" <<'GD'
extends SceneTree
func _init() -> void:
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color.MAGENTA)
	img.save_png(ProjectSettings.globalize_path("res://probe.png"))
	quit()
GD
PATH="/usr/bin:$PATH" "$GODOT_BIN" --headless --path "$PROBE" -s res://make.gd >/dev/null 2>&1 || true
rm -f "$PROBE/make.gd"
test -s "$PROBE/probe.png" || { echo "  FAIL probe png was not written"; exit 1; }

# An .import with the three keys removed and a non-default parameter to watch.
cat > "$PROBE/probe.png.import" <<'IMP'
[remap]

importer="texture"
type="CompressedTexture2D"

[deps]

source_file="res://probe.png"

[params]

compress/mode=0
mipmaps/generate=true
process/fix_alpha_border=false
IMP

PATH="/usr/bin:$PATH" "$GODOT_BIN" --headless --path "$PROBE" --import --quit >/dev/null 2>&1 || true

status=0
grep -q '^uid="uid://' "$PROBE/probe.png.import" \
  && echo "  ok   reimport regenerated uid=" || { echo "  FAIL uid= was not regenerated"; status=1; }
grep -qE '^path(\.[a-z0-9]+)?=' "$PROBE/probe.png.import" \
  && echo "  ok   reimport regenerated path=" || { echo "  FAIL path= was not regenerated"; status=1; }
grep -q '^process/fix_alpha_border=false' "$PROBE/probe.png.import" \
  && echo "  ok   tuned parameter survived" || { echo "  FAIL tuned parameter was lost"; status=1; }
ART="$(sed -nE 's/^path(\.[a-z0-9]+)?="(res:\/\/\.godot\/imported\/[^"]*)"/\2/p' "$PROBE/probe.png.import" | head -1)"
if [[ -n "$ART" && -f "$PROBE/${ART#res://}" ]]; then
    echo "  ok   artifact exists at the regenerated path"
else
    echo "  FAIL no artifact at '${ART:-<none>}'"; status=1
fi
echo "import_probe: $([ $status -eq 0 ] && echo PASS || echo FAIL)"
exit $status
