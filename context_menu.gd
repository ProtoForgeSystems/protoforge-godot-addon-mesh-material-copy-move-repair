extends EditorContextMenuPlugin
## FileSystem dock items. Copy cannot be automatic — Duplicate emits no signal — and Repair exists
## for assets a past move already broke. Uses only the 4.4-documented surface.

var handler: Callable


func _popup_menu(paths: PackedStringArray) -> void:
	if not handler.is_valid() or not handler.call("any_handled", paths):
		return
	add_context_menu_item("Copy with dependencies…", func(p): handler.call("copy", p))
	add_context_menu_item("Repair sidecars", func(p): handler.call("repair", p))
