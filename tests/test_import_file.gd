extends SceneTree
## Headless: the .import text transform. Move preserves uid, copy drops it, both drop artifact keys
## and repoint every occurrence of the old source path.

const ImportFile := preload("res://addons/sidecar/import_file.gd")

const SAMPLE := """[remap]

importer="texture"
type="CompressedTexture2D"
uid="uid://dnuammn6t11vi"
path.s3tc="res://.godot/imported/t.png-9192a384.s3tc.ctex"
path.etc2="res://.godot/imported/t.png-9192a384.etc2.ctex"
metadata={
"imported_formats": ["s3tc_bptc", "etc2_astc"],
"vram_texture": true
}

[deps]

source_file="res://old/dir/t.png"
dest_files=["res://.godot/imported/t.png-9192a384.s3tc.ctex", "res://.godot/imported/t.png-9192a384.etc2.ctex"]

[params]

compress/mode=2
compress/normal_map=1
roughness/mode=1
roughness/src_normal="res://old/dir/t.png"
detect_3d/compress_to=0
"""

var _failures := 0


func _check(ok: bool, name: String) -> void:
	if ok:
		print("  ok   %s" % name)
	else:
		_failures += 1
		print("  FAIL %s" % name)


func _init() -> void:
	var moved: String = ImportFile.reconcile(SAMPLE, "res://old/dir/t.png", "res://new/dir/t.png", true)
	_check(moved.contains('uid="uid://dnuammn6t11vi"'), "move: uid preserved")
	_check(moved.contains('source_file="res://new/dir/t.png"'), "move: source_file repointed")
	_check(moved.contains('roughness/src_normal="res://new/dir/t.png"'), "move: every occurrence repointed")
	_check(not moved.contains("res://old/dir"), "move: no stale path anywhere")
	_check(not moved.contains("path.s3tc="), "move: artifact path keys dropped")
	_check(not moved.contains("dest_files="), "move: dest_files dropped")
	_check(moved.contains("compress/normal_map=1"), "move: tuned params survive")
	_check(moved.contains('"imported_formats"'), "move: metadata block survives")
	_check(moved.contains("detect_3d/compress_to=0"), "move: last line survives")

	var copied: String = ImportFile.reconcile(SAMPLE, "res://old/dir/t.png", "res://new/dir/t.png", false)
	_check(not copied.contains("uid="), "copy: uid dropped so Godot mints a fresh one")
	_check(copied.contains('source_file="res://new/dir/t.png"'), "copy: source_file repointed")
	_check(copied.contains("compress/mode=2"), "copy: tuned params survive")

	# A scene .import (a .gltf's) has a bare `path=` rather than the per-format variants.
	var scene_import := "[remap]\n\nimporter=\"scene\"\nuid=\"uid://abc\"\npath=\"res://.godot/imported/m.gltf-dead.scn\"\n\n[deps]\n\nsource_file=\"res://old/m.gltf\"\ndest_files=[\"res://.godot/imported/m.gltf-dead.scn\"]\n\n[params]\n\nnodes/root_scale=1.0\n"
	var scene_moved: String = ImportFile.reconcile(scene_import, "res://old/m.gltf", "res://new/m.gltf", true)
	_check(not scene_moved.contains("path="), "scene: bare path= dropped")
	_check(scene_moved.contains("nodes/root_scale=1.0"), "scene: params survive")
	_check(scene_moved.contains('uid="uid://abc"'), "scene move: uid preserved")

	# Idempotence: reconciling an already-reconciled file changes nothing further.
	_check(ImportFile.reconcile(moved, "res://new/dir/t.png", "res://new/dir/t.png", true) == moved, "reconcile is idempotent")

	print("import_file tests: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	quit(0 if _failures == 0 else 1)
