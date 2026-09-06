extends FileDialog
## Asks for the destination directory of a copy-with-dependencies.


func _init() -> void:
	title = "Copy with dependencies to…"
	file_mode = FileDialog.FILE_MODE_OPEN_DIR
	access = FileDialog.ACCESS_RESOURCES
	current_dir = "res://"
