extends RefCounted
## Base class for sidecar resolvers. A resolver knows how to read one asset format and name the
## sibling files it references by URI — the files Godot's dependency graph cannot see.


## True if this resolver understands `path`.
func can_handle(_path: String) -> bool:
	return false


## Returns { "sidecars": PackedStringArray, "skipped": Array }.
## `sidecars` are existing paths, deduped, never including `path` itself.
## `skipped` entries are { "uri": String, "reason": String } for the report.
##
## `uri_base_dir` overrides the directory the document's relative URIs resolve against. It
## exists because those are two different questions: after a FileSystem-dock move the .gltf is
## already at its new home while its sidecars are still at the old one, so the document is read
## from one directory and its URIs must be resolved against another. Default "" means "the
## document's own directory", which is right everywhere else.
func collect(_path: String, _uri_base_dir: String = "") -> Dictionary:
	return {"sidecars": PackedStringArray(), "skipped": []}
