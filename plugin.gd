@tool
extends EditorPlugin
## Sidecar: carries a .gltf's .bin and textures through a FileSystem-dock move, copies an asset
## with its dependencies, and repairs assets broken by a past move.
##
## Godot's dependency graph cannot see a glTF's sidecars — they are named by relative URI inside
## the document — so the dock moves the .gltf alone and leaves a poisoned .import behind
## (godotengine/godot#43043). This reacts to the move rather than replacing it, because the dock's
## drag-and-drop is not overridable and `files_moved` gives us both paths exactly.

const GltfResolver := preload("res://addons/sidecar/gltf_resolver.gd")
const SharedLookup := preload("res://addons/sidecar/shared_lookup.gd")
const Plan := preload("res://addons/sidecar/plan.gd")
const Executor := preload("res://addons/sidecar/executor.gd")
const ContextMenu := preload("res://addons/sidecar/context_menu.gd")
const CopyDialog := preload("res://addons/sidecar/copy_dialog.gd")

var _resolvers := [GltfResolver.new()]
var _menu: EditorContextMenuPlugin
var _dialog: FileDialog
var _busy := false
var _pending: PackedStringArray
var _deferred: Array = []


func _enter_tree() -> void:
	EditorInterface.get_file_system_dock().files_moved.connect(_on_files_moved)
	EditorInterface.get_resource_filesystem().filesystem_changed.connect(_on_filesystem_changed)
	_menu = ContextMenu.new()
	_menu.handler = _on_menu
	add_context_menu_plugin(EditorContextMenuPlugin.CONTEXT_SLOT_FILESYSTEM, _menu)
	_dialog = CopyDialog.new()
	_dialog.dir_selected.connect(_on_copy_target_chosen)
	EditorInterface.get_base_control().add_child(_dialog)


func _exit_tree() -> void:
	EditorInterface.get_file_system_dock().files_moved.disconnect(_on_files_moved)
	EditorInterface.get_resource_filesystem().filesystem_changed.disconnect(_on_filesystem_changed)
	_deferred.clear()
	remove_context_menu_plugin(_menu)
	_menu = null
	_dialog.queue_free()
	_dialog = null


func _resolver_for(path: String) -> RefCounted:
	for r in _resolvers:
		if r.can_handle(path):
			return r
	return null


func _on_menu(what: String, paths: PackedStringArray) -> Variant:
	match what:
		"any_handled":
			for p in paths:
				if _resolver_for(p) != null:
					return true
			return false
		"copy":
			if paths.is_empty():
				return null
			_pending = paths
			# Open where the asset lives, not at res://. A copy almost always lands in a
			# sibling folder, and starting at the project root makes the user navigate back
			# down to where they already were.
			_dialog.current_dir = paths[0].get_base_dir()
			_dialog.popup_centered_ratio(0.5)
		"repair":
			for p in paths:
				_run(Plan.Mode.REPAIR, p, p)
	return null


func _on_copy_target_chosen(dir: String) -> void:
	for p in _pending:
		_run(Plan.Mode.COPY, p, dir.path_join(p.get_file()))
	_pending = PackedStringArray()


func _on_files_moved(old_file: String, new_file: String) -> void:
	# Belt and braces. Executor moves files through DirAccess, which does not route through the
	# dock and so cannot emit this signal -- but the guard costs nothing and the day some path
	# does move a file through the dock, this is what stops the recursion.
	if _busy:
		return
	_run(Plan.Mode.MOVE, old_file, new_file)


## Drains the runs that arrived while the editor was mid-scan. One connection made in
## _enter_tree and dropped in _exit_tree, rather than a bound one-shot per deferred run: the
## EditorFileSystem is the editor's own long-lived object, so a per-run connection would
## outlive the plugin being disabled and fire into a freed instance.
func _on_filesystem_changed() -> void:
	if _deferred.is_empty():
		return
	var queued := _deferred.duplicate()
	_deferred.clear()
	for r in queued:
		_run(r.mode, r.from, r.to)


func _run(mode: int, from: String, to: String) -> void:
	var resolver := _resolver_for(from)
	if resolver == null:
		return
	var efs := EditorInterface.get_resource_filesystem()
	if efs.is_scanning() or efs.is_importing():
		# Retry once the editor is idle rather than racing its scan. Queued, not connected --
		# see _on_filesystem_changed for why a per-run one-shot would leak past _exit_tree.
		_deferred.append({"mode": mode, "from": from, "to": to})
		return

	# On a move the dock has already relocated the .gltf, but its sidecars are still in the OLD
	# directory -- so read the document from its new home and resolve its URIs against the old
	# one. Resolving against the new directory finds nothing at all, every sidecar reports
	# "missing file", and the addon silently does nothing. Measured, 2026-09-06.
	var read_from := to if mode == Plan.Mode.MOVE else from
	var uri_base := from.get_base_dir() if mode == Plan.Mode.MOVE else ""
	var found: Dictionary = resolver.collect(read_from, uri_base)
	if found.sidecars.is_empty() and found.skipped.is_empty():
		return

	var is_shared := SharedLookup.make(_resolvers, efs.get_filesystem(), read_from)
	var plan: Dictionary = Plan.build(mode, from, to, found.sidecars, is_shared)

	# No early return on an empty plan: a Repair whose sidecars are genuinely missing produces
	# no actions, and returning here left the user staring at an empty Output panel after
	# explicitly asking for a repair. The skipped lines below are the answer they wanted.
	var report: Array = []
	if not plan.actions.is_empty():
		_busy = true
		report = Executor.apply(plan.actions)
		_busy = false

	# Report BEFORE handing anything to the importer. A reimport logs errors of its own -- a
	# glTF whose buffer is genuinely still missing, say -- and those read as unexplained noise
	# when they arrive ahead of the lines saying what was done and what was skipped. Printing
	# first puts them in causal order: here is what changed, then here is what the engine made
	# of it.
	print_rich("[b]glTF Copy/Move/Repair[/b] %s %s" % [Plan.Mode.keys()[mode].to_lower(), to])
	for line in report:
		print("  " + line)
	for note in plan.notes:
		print("  note: " + note)
	for s in found.skipped:
		print("  skipped %s — %s" % [s.uri, s.reason])

	if not plan.actions.is_empty():
		# Only files Godot actually imports have a .import sibling. Handing it anything else --
		# a .bin, notably -- makes it log "BUG: File queued for import, but can't be imported,
		# importer for type '' not found" on every single move, which reads as this addon being
		# broken. Measured in the editor, 2026-09-06.
		var importable := PackedStringArray()
		for path in Executor.touched_paths(plan.actions):
			if FileAccess.file_exists(path + ".import"):
				importable.append(path)
				efs.update_file(path)
		if not importable.is_empty():
			efs.reimport_files(importable)
