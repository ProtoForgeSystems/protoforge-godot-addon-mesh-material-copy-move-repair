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


func _enter_tree() -> void:
	EditorInterface.get_file_system_dock().files_moved.connect(_on_files_moved)
	_menu = ContextMenu.new()
	_menu.handler = _on_menu
	add_context_menu_plugin(EditorContextMenuPlugin.CONTEXT_SLOT_FILESYSTEM, _menu)
	_dialog = CopyDialog.new()
	_dialog.dir_selected.connect(_on_copy_target_chosen)
	EditorInterface.get_base_control().add_child(_dialog)


func _exit_tree() -> void:
	EditorInterface.get_file_system_dock().files_moved.disconnect(_on_files_moved)
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
			_pending = paths
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
	# Our own transfers fire this signal too.
	if _busy:
		return
	_run(Plan.Mode.MOVE, old_file, new_file)


func _run(mode: int, from: String, to: String) -> void:
	var resolver := _resolver_for(from)
	if resolver == null:
		return
	var efs := EditorInterface.get_resource_filesystem()
	if efs.is_scanning() or efs.is_importing():
		# Retry once the editor is idle rather than racing its scan.
		efs.filesystem_changed.connect(_run.bind(mode, from, to), CONNECT_ONE_SHOT)
		return

	# On a move the file is already at its new home; read the glTF from wherever it now is.
	var read_from := to if mode == Plan.Mode.MOVE else from
	var found: Dictionary = resolver.collect(read_from)
	if found.sidecars.is_empty() and found.skipped.is_empty():
		return

	var is_shared := SharedLookup.make(_resolvers, efs.get_filesystem(), read_from)
	var plan: Dictionary = Plan.build(mode, from, to, found.sidecars, is_shared)
	if plan.actions.is_empty():
		return

	_busy = true
	var report: Array = Executor.apply(plan.actions)
	_busy = false

	var touched := Executor.touched_paths(plan.actions)
	for path in touched:
		efs.update_file(path)
	efs.reimport_files(touched)

	print_rich("[b]Sidecar[/b] %s %s" % [Plan.Mode.keys()[mode].to_lower(), to])
	for line in report:
		print("  " + line)
	for note in plan.notes:
		print("  note: " + note)
	for s in found.skipped:
		print("  skipped %s — %s" % [s.uri, s.reason])
