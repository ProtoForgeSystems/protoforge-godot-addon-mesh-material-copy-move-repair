@tool
extends EditorPlugin
## Sidecar: carries a .gltf's .bin and textures through a FileSystem-dock move, copies an asset
## with its dependencies, and repairs assets broken by a past move.
##
## Godot's dependency graph cannot see a glTF's sidecars — they are named by relative URI inside
## the document, not in the .import — so the dock moves the .gltf alone and leaves a poisoned
## .import behind (godotengine/godot#43043).


func _enter_tree() -> void:
	pass


func _exit_tree() -> void:
	pass
