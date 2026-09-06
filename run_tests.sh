#!/usr/bin/env bash
# Headless GDScript tests. Run from inside a host Godot project that mounts this addon at
# <project>/addons/<name>. Exit 1 on any failure.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAME="$(basename "$ROOT")"
PROJECT="$(cd "$ROOT/../.." && pwd)"
if [[ ! -f "$PROJECT/project.godot" ]]; then
    echo "No project.godot at $PROJECT — mount this addon at <godot project>/addons/$NAME" >&2
    exit 1
fi
if [[ -n "${GODOT:-}" ]]; then GODOT_BIN="$GODOT"
elif [[ "$(uname -s)" == "Darwin" ]]; then GODOT_BIN="/Applications/Godot_mono.app/Contents/MacOS/Godot"
else GODOT_BIN="$HOME/Applications/godot/Godot_v4.7.1-stable_mono_linux.x86_64"; fi
# Godot writes a .uid beside each script on import, and those are tracked (see Global
# Constraints). A missing one means a script was added since the last import, so reimport --
# incremental, and cheap on an already-imported project.
missing_uid=0
for f in "$ROOT"/*.gd "$ROOT"/tests/*.gd; do
    [[ -e "$f" ]] || continue
    [[ -f "$f.uid" ]] || missing_uid=1
done
if [[ ! -f "$PROJECT/.godot/global_script_class_cache.cfg" || $missing_uid -eq 1 ]]; then
    PATH="/usr/bin:$PATH" "$GODOT_BIN" --headless --path "$PROJECT" --import --quit >/dev/null 2>&1 || true
fi
status=0
for t in test_resolver_base; do
    # Godot exits 0 when a script fails to LOAD -- a bad preload, a syntax error, or a name
    # typo'd in this loop all produce a silent green. Only a suite that ran to completion
    # prints its own "tests: PASS" line, so require it as well as the exit code.
    out="$(PATH="/usr/bin:$PATH" "$GODOT_BIN" --headless --path "$PROJECT" \
        -s "res://addons/$NAME/tests/$t.gd" 2>&1)" || status=1
    printf '%s\n' "$out" | grep -v "^$" || true
    if ! grep -q "tests: PASS" <<<"$out"; then
        echo "  FAIL $t reported no PASS line -- it failed, or never ran at all"
        status=1
    fi
done
exit $status
