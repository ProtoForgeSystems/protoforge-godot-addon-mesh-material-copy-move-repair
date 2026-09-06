extends SceneTree
## Headless: the executor moves, copies and reconciles real files on disk, under user://.

const Fixture := preload("res://addons/sidecar/tests/fixture.gd")
const Plan := preload("res://addons/sidecar/plan.gd")
const Executor := preload("res://addons/sidecar/executor.gd")

var _failures := 0


func _check(ok: bool, name: String) -> void:
	if ok:
		print("  ok   %s" % name)
	else:
		_failures += 1
		print("  FAIL %s" % name)


func _import_for(source: String, uid: String) -> String:
	return "[remap]\n\nimporter=\"texture\"\nuid=\"%s\"\npath=\"user://x-dead.ctex\"\n\n[deps]\n\nsource_file=\"%s\"\ndest_files=[\"user://x-dead.ctex\"]\n\n[params]\n\ncompress/mode=2\n" % [uid, source]


func _init() -> void:
	var base := Fixture.reset()
	var src := base.path_join("src")
	var dst := base.path_join("dst")
	DirAccess.make_dir_recursive_absolute(dst)

	Fixture.write_blob("src/m.bin")
	Fixture.write_blob("src/own.png")
	Fixture.write_blob("src/shared.png")
	Fixture.write_raw("src/own.png.import", _import_for(src.path_join("own.png"), "uid://own1"))
	Fixture.write_raw("src/shared.png.import", _import_for(src.path_join("shared.png"), "uid://shr1"))

	var actions := [
		{"op": Plan.Op.MOVE, "from": src.path_join("m.bin"), "to": dst.path_join("m.bin"), "keep_uid": true},
		{"op": Plan.Op.MOVE, "from": src.path_join("own.png"), "to": dst.path_join("own.png"), "keep_uid": true},
		{"op": Plan.Op.COPY, "from": src.path_join("shared.png"), "to": dst.path_join("shared.png"), "keep_uid": false},
	]
	var report: Array = Executor.apply(actions)

	_check(FileAccess.file_exists(dst.path_join("m.bin")), "bin landed at the destination")
	_check(not FileAccess.file_exists(src.path_join("m.bin")), "moved bin no longer at the source")
	_check(not FileAccess.file_exists(src.path_join("own.png.import")), "moved .import sibling travelled")
	_check(FileAccess.file_exists(src.path_join("shared.png")), "copied sidecar left in place")
	_check(FileAccess.file_exists(dst.path_join("shared.png.import")), "copy got its own .import")

	var moved_import := FileAccess.get_file_as_string(dst.path_join("own.png.import"))
	_check(moved_import.contains("uid://own1"), "moved .import kept its uid")
	_check(moved_import.contains(dst.path_join("own.png")), "moved .import repointed at the new path")
	_check(not moved_import.contains("dest_files="), "moved .import lost its artifact keys")
	_check(moved_import.contains("compress/mode=2"), "moved .import kept its params")

	var copied_import := FileAccess.get_file_as_string(dst.path_join("shared.png.import"))
	_check(not copied_import.contains("uid="), "copied .import dropped its uid")
	_check(FileAccess.get_file_as_string(src.path_join("shared.png.import")).contains("uid://shr1"), "the original .import was not touched")

	_check(report.size() == 3, "one report line per action (got %d)" % report.size())
	_check(not FileAccess.file_exists(dst.path_join("m.bin.import")), "no .import invented for the bin")

	# Missing source: reported, not fatal.
	var missing: Array = Executor.apply([{"op": Plan.Op.MOVE, "from": src.path_join("gone.png"), "to": dst.path_join("gone.png"), "keep_uid": true}])
	_check(missing.size() == 1 and missing[0].contains("missing"), "missing source reported, not fatal")

	# Ordering: the primary is handed to the editor last so its dependencies exist first.
	var ordered: PackedStringArray = Executor.touched_paths([
		{"op": Plan.Op.RECONCILE, "from": src.path_join("m.gltf"), "to": dst.path_join("m.gltf"), "keep_uid": true},
		{"op": Plan.Op.MOVE, "from": src.path_join("m.bin"), "to": dst.path_join("m.bin"), "keep_uid": true},
	])
	_check(ordered.size() == 2 and ordered[1].ends_with("m.gltf"), "primary reimports last")

	Fixture.rm_rf(Fixture.DIR)
	print("executor tests: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	quit(0 if _failures == 0 else 1)
