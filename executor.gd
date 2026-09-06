extends RefCounted
## Performs the actions a SidecarPlan decided: moves and copies files, carries their .import
## siblings, and reconciles each one. Deliberately free of editor API so it can be tested headless;
## telling EditorFileSystem about the result is the caller's job (see touched_paths).

const ImportFile := preload("res://addons/sidecar/import_file.gd")
const Plan := preload("res://addons/sidecar/plan.gd")


static func apply(actions: Array) -> Array:
	var report := []
	for a in actions:
		match a.op:
			Plan.Op.MOVE:
				report.append(_transfer(a, true))
			Plan.Op.COPY:
				report.append(_transfer(a, false))
			Plan.Op.RECONCILE:
				report.append(_reconcile_only(a))
	return report


## Destination paths the caller should hand to EditorFileSystem, with the reconciled primary last
## so its dependencies are on disk before it is parsed.
static func touched_paths(actions: Array) -> PackedStringArray:
	var out := PackedStringArray()
	var primary := PackedStringArray()
	for a in actions:
		if a.op == Plan.Op.RECONCILE:
			primary.append(a.to)
		else:
			out.append(a.to)
	out.append_array(primary)
	return out


static func _transfer(a: Dictionary, remove_source: bool) -> String:
	if not FileAccess.file_exists(a.from):
		return "skipped %s — missing" % a.from
	DirAccess.make_dir_recursive_absolute(a.to.get_base_dir())
	var err := DirAccess.copy_absolute(a.from, a.to)
	if err != OK:
		return "FAILED %s -> %s (error %d)" % [a.from, a.to, err]
	_carry_import(a, remove_source)
	if remove_source:
		DirAccess.remove_absolute(a.from)
		return "moved %s -> %s" % [a.from, a.to]
	return "copied %s -> %s" % [a.from, a.to]


static func _carry_import(a: Dictionary, remove_source: bool) -> void:
	# A .bin has no .import, and that is not an error.
	var from_import: String = a.from + ".import"
	if not FileAccess.file_exists(from_import):
		return
	_write(a.to + ".import", ImportFile.reconcile(FileAccess.get_file_as_string(from_import), a.from, a.to, a.keep_uid))
	if remove_source:
		DirAccess.remove_absolute(from_import)


static func _reconcile_only(a: Dictionary) -> String:
	var import_path: String = a.to + ".import"
	if not FileAccess.file_exists(import_path):
		return "skipped %s — no .import to reconcile" % a.to
	_write(import_path, ImportFile.reconcile(FileAccess.get_file_as_string(import_path), a.from, a.to, a.keep_uid))
	return "reconciled %s" % a.to


static func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()
