extends SceneTree
## Headless: the executor moves, copies and reconciles real files on disk, under user://.

const Fixture := preload("res://addons/mesh_material_copy_move_repair/tests/fixture.gd")
const Plan := preload("res://addons/mesh_material_copy_move_repair/plan.gd")
const Executor := preload("res://addons/mesh_material_copy_move_repair/executor.gd")

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
		{"op": Plan.Op.RECONCILE, "from": src.path_join("m.gltf"), "to": dst.path_join("m.gltf"), "keep_uid": true, "primary": true},
		{"op": Plan.Op.MOVE, "from": src.path_join("m.bin"), "to": dst.path_join("m.bin"), "keep_uid": true},
	])
	_check(ordered.size() == 2 and ordered[1].ends_with("m.gltf"), "primary reimports last")

	# ...and on a COPY, where the primary is a COPY exactly like its sidecars. Keying the order
	# on RECONCILE put it first, and Godot then imported the .gltf before its textures existed.
	var copy_order: PackedStringArray = Executor.touched_paths([
		{"op": Plan.Op.COPY, "from": src.path_join("m.gltf"), "to": dst.path_join("m.gltf"), "keep_uid": false, "primary": true},
		{"op": Plan.Op.COPY, "from": src.path_join("t.png"), "to": dst.path_join("t.png"), "keep_uid": false},
	])
	_check(copy_order.size() == 2 and copy_order[1].ends_with("m.gltf"), "primary reimports last on a COPY too")

	# An existing destination is never clobbered, and on a MOVE the source must survive --
	# otherwise one ordinary accident destroys both copies.
	Fixture.write_raw("src/keep.png", "SOURCE")
	Fixture.write_raw("dst/keep.png", "PRECIOUS")
	var clash: Array = Executor.apply([{"op": Plan.Op.MOVE, "from": src.path_join("keep.png"), "to": dst.path_join("keep.png"), "keep_uid": true}])
	_check(FileAccess.get_file_as_string(dst.path_join("keep.png")) == "PRECIOUS", "an existing destination is not overwritten")
	_check(FileAccess.file_exists(src.path_join("keep.png")), "a skipped move does not delete its source")
	_check(clash.size() == 1 and clash[0].contains("already exists"), "the collision is reported (%s)" % clash[0])

	# RECONCILE through apply(), which the touched_paths ordering check alone never exercises.
	Fixture.write_blob("dst/lone.png")
	Fixture.write_raw("dst/lone.png.import", _import_for(src.path_join("lone.png"), "uid://lone1"))
	var rec: Array = Executor.apply([{"op": Plan.Op.RECONCILE, "from": src.path_join("lone.png"), "to": dst.path_join("lone.png"), "keep_uid": true}])
	var rec_text := FileAccess.get_file_as_string(dst.path_join("lone.png.import"))
	_check(rec.size() == 1 and rec[0].begins_with("reconciled"), "reconcile-in-place is reported")
	_check(rec_text.contains(dst.path_join("lone.png")), "reconcile repointed the .import at the new path")
	_check(rec_text.contains("uid://lone1"), "reconcile kept the uid")

	# A RECONCILE with no .import to fix says nothing -- a .bin is not repairable, and a missing
	# sidecar is already reported separately by the resolver as "missing file".
	Fixture.write_blob("dst/bare.png")
	var bare: Array = Executor.apply([{"op": Plan.Op.RECONCILE, "from": src.path_join("bare.png"), "to": dst.path_join("bare.png"), "keep_uid": true}])
	_check(bare.is_empty(), "a reconcile with no .import says nothing — a .bin is not repairable")

	# --- Copying OUT of the project, into another project's directory -------------------------
	# The destination is a real OS path, which is what the ACCESS_FILESYSTEM picker returns. It
	# is placed inside the fixture dir so rm_rf still cleans it.
	var ext_dir := ProjectSettings.globalize_path(Fixture.DIR).path_join("ext")
	_check(Executor.is_external(ext_dir), "an absolute OS path is external")
	_check(not Executor.is_external("res://a/b.gltf"), "a res:// path is not external")
	_check(not Executor.is_external("user://a/b.gltf"), "a user:// path is not external")

	# EditorFileSystem indexes res:// and nothing else, so external destinations must not reach
	# it -- while the in-project ones still come back, still with the primary last.
	var mixed := [
		{"op": Plan.Op.COPY, "from": src.path_join("x.gltf"), "to": ext_dir.path_join("x.gltf"), "keep_uid": false, "primary": true},
		{"op": Plan.Op.COPY, "from": src.path_join("x.png"), "to": ext_dir.path_join("x.png"), "keep_uid": false},
		{"op": Plan.Op.COPY, "from": src.path_join("in.png"), "to": dst.path_join("in.png"), "keep_uid": false},
	]
	var handed: PackedStringArray = Executor.touched_paths(mixed)
	_check(handed.size() == 1 and handed[0].ends_with("in.png"), "external destinations are not handed to the editor")
	var dirs: PackedStringArray = Executor.external_dirs(mixed)
	_check(dirs.size() == 1 and dirs[0] == ext_dir, "external_dirs reports the directory once (got %s)" % str(dirs))
	_check(Executor.external_dirs([mixed[2]]).is_empty(), "an all-in-project run reports no external dirs")

	# ...and the copy itself really lands there, sidecar and .import included. This is the whole
	# point: a library project copying an asset into a different project's kitbash.
	Fixture.write_blob("src/out.png")
	Fixture.write_blob("src/out.bin")
	Fixture.write_raw("src/out.png.import", _import_for(src.path_join("out.png"), "uid://out1"))
	var out_report: Array = Executor.apply([
		{"op": Plan.Op.COPY, "from": src.path_join("out.png"), "to": ext_dir.path_join("out.png"), "keep_uid": false, "primary": true},
		{"op": Plan.Op.COPY, "from": src.path_join("out.bin"), "to": ext_dir.path_join("out.bin"), "keep_uid": false},
	])
	_check(FileAccess.file_exists(ext_dir.path_join("out.png")), "the asset landed outside the project")
	_check(FileAccess.file_exists(ext_dir.path_join("out.bin")), "its sidecar followed it out")
	_check(FileAccess.file_exists(ext_dir.path_join("out.png.import")), "its .import was carried out")
	var out_text := FileAccess.get_file_as_string(ext_dir.path_join("out.png.import"))
	_check(not out_text.contains("uid://out1"), "the carried .import dropped the source uid — a copy must not share one")
	_check(out_text.contains("compress/mode=2"), "the carried .import kept its tuned params")
	_check(out_text.contains(ext_dir.path_join("out.png")), "the carried .import points at the new location")
	var out_failures := 0
	for line in out_report:
		if not String(line).begins_with("copied"):
			out_failures += 1
	_check(out_failures == 0, "the external copy reported no failures (%s)" % str(out_report))

	Fixture.rm_rf(Fixture.DIR)
	print("executor tests: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	quit(0 if _failures == 0 else 1)
