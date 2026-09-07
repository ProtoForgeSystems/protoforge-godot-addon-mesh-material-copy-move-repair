extends RefCounted
## Performs the actions a Plan decided: moves and copies files, carries their .import
## siblings, and reconciles each one. Deliberately free of editor API so it can be tested headless;
## telling EditorFileSystem about the result is the caller's job (see touched_paths).

const ImportFile := preload("res://addons/mesh_material_copy_move_repair/import_file.gd")
const Plan := preload("res://addons/mesh_material_copy_move_repair/plan.gd")


static func apply(actions: Array) -> Array:
	var report := []
	for a in actions:
		var line := ""
		match a.op:
			Plan.Op.MOVE:
				line = _transfer(a, true)
			Plan.Op.COPY:
				line = _transfer(a, false)
			Plan.Op.RECONCILE:
				line = _reconcile_only(a)
		# An empty line means "nothing to say" -- a .bin has no .import and never will, so a
		# repair reporting "no .import to reconcile" for it every time is noise about a file
		# that is not repairable in the first place.
		if not line.is_empty():
			report.append(line)
	return report


## Destination paths the caller should hand to EditorFileSystem, with the asset itself LAST so
## its dependencies are on disk before Godot parses it.
##
## Keyed on the primary flag, never on the op. On a COPY the asset is a COPY exactly like its
## sidecars, so keying on RECONCILE put it FIRST and Godot imported the .gltf before its
## textures existed as resources -- "Failed loading resource", once per texture, on every single
## copy. A move looked clean only because its primary happens to be a RECONCILE. Measured in
## the editor, 2026-09-06.
##
## External destinations are omitted -- see is_external(). They are still copied; only the
## notification to EditorFileSystem is skipped, and external_dirs() is what lets the caller
## say so out loud.
static func touched_paths(actions: Array) -> PackedStringArray:
	var out := PackedStringArray()
	var primary := PackedStringArray()
	for a in actions:
		if is_external(a.to):
			continue
		if a.get("primary", false):
			primary.append(a.to)
		else:
			out.append(a.to)
	out.append_array(primary)
	return out


## Whether a path lives outside Godot's virtual filesystem -- an absolute OS path, which is
## what a copy into ANOTHER project's directory produces.
##
## Those are copied like any other destination but are never handed to EditorFileSystem, which
## indexes res:// and nothing else. Nothing is lost by skipping it: the destination project
## imports them on its own next scan, and Godot repoints the carried .import's source_file at
## that project's res:// path by itself -- measured on 4.7.1, 2026-09-07, tuned import params
## intact.
static func is_external(path: String) -> bool:
	return not path.begins_with("res://") and not path.begins_with("user://")


## The external destination directories a run wrote to, de-duplicated and sorted, for the caller
## to report. An addon whose whole failure surface is "nothing happened" has to say out loud
## when it deliberately did not import something.
static func external_dirs(actions: Array) -> PackedStringArray:
	var seen := {}
	for a in actions:
		if not is_external(a.to):
			continue
		seen[String(a.to).get_base_dir()] = true
	var out := PackedStringArray(seen.keys())
	out.sort()
	return out


static func _transfer(a: Dictionary, remove_source: bool) -> String:
	if not FileAccess.file_exists(a.from):
		return "skipped %s — missing" % a.from
	# Never clobber. An existing destination is usually the benign case — a sidecar shared with
	# an asset copied here earlier — and overwriting it on a MOVE would destroy that file and
	# then delete the source that could have restored it. One ordinary accident, two files gone.
	if FileAccess.file_exists(a.to):
		return "skipped %s — %s already exists" % [a.from, a.to]
	DirAccess.make_dir_recursive_absolute(a.to.get_base_dir())
	var err := DirAccess.copy_absolute(a.from, a.to)
	if err != OK:
		return "FAILED %s -> %s (error %d)" % [a.from, a.to, err]
	var carried := _carry_import(a, remove_source)
	if not carried.is_empty():
		return carried
	if remove_source:
		# A source that could not be removed leaves a copy, not a move -- and its .import is
		# already gone, so Godot would reimport it with default settings and silently drop
		# whatever was tuned. Say what actually happened.
		var rm := DirAccess.remove_absolute(a.from)
		if rm != OK:
			return "copied %s -> %s (source NOT removed, error %d)" % [a.from, a.to, rm]
		return "moved %s -> %s" % [a.from, a.to]
	return "copied %s -> %s" % [a.from, a.to]


## Returns "" on success, or a report line describing the failure. On failure the source is
## left untouched: an asset whose .import did not follow is recoverable, one deleted from its
## only home is not.
static func _carry_import(a: Dictionary, remove_source: bool) -> String:
	# A .bin has no .import, and that is not an error.
	var from_import: String = a.from + ".import"
	if not FileAccess.file_exists(from_import):
		return ""
	var text := ImportFile.reconcile(FileAccess.get_file_as_string(from_import), a.from, a.to, a.keep_uid)
	var err := _write(a.to + ".import", text)
	if err != OK:
		return "FAILED %s.import -> %s.import (error %d)" % [a.from, a.to, err]
	if remove_source:
		DirAccess.remove_absolute(from_import)
	return ""


## Returns "" when there is nothing to reconcile. A .bin has no .import and never will; the
## resolver already reports a sidecar that is genuinely MISSING, so silence here is the right
## answer rather than a line about every unimportable file on every repair.
static func _reconcile_only(a: Dictionary) -> String:
	var import_path: String = a.to + ".import"
	if not FileAccess.file_exists(import_path):
		return ""
	var text := ImportFile.reconcile(FileAccess.get_file_as_string(import_path), a.from, a.to, a.keep_uid)
	var err := _write(import_path, text)
	if err != OK:
		return "FAILED reconciling %s (error %d)" % [import_path, err]
	return "reconciled %s" % a.to


## FileAccess.open() returns null on failure; calling store_string() on that is an unhandled
## script error, not an exception this can catch — so the null check is the error handling.
static func _write(path: String, text: String) -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(text)
	f.close()
	return OK
