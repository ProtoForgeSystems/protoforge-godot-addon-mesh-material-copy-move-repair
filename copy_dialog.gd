extends FileDialog
## Asks for the destination directory of a copy-with-dependencies.
##
## ACCESS_FILESYSTEM rather than ACCESS_RESOURCES, so the destination may be another project.
## A shared asset library feeding several games is a normal arrangement, and copying an asset
## out of it is exactly this addon's job -- doing it by hand means carrying the .bin and every
## texture and reconciling each .import, which is the operation the addon exists to automate.
##
## Nothing else in the chain needed changing for it: gltf_resolver clamps the SOURCE document's
## URIs to its own root, which an in-project source satisfies by construction; plan.gd is pure
## string work; and executor already writes through the DirAccess *_absolute family. Measured
## end to end on 4.7.1, 2026-09-07 -- 6 sidecars resolved, 0 skipped, asset intact at the
## destination.
##
## The picker still OPENS at the asset's own directory (see plugin.gd's "copy" branch), so the
## wider access is reach when it is wanted, not a project root nobody asked to leave.


func _init() -> void:
	title = "Copy with dependencies to…"
	file_mode = FileDialog.FILE_MODE_OPEN_DIR
	access = FileDialog.ACCESS_FILESYSTEM
	# A real OS path, because ACCESS_FILESYSTEM does not resolve "res://". Overwritten per-copy
	# by the caller; this is only what an unparented dialog would show.
	current_dir = ProjectSettings.globalize_path("res://")
