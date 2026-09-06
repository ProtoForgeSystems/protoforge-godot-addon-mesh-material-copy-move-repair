extends RefCounted
## Base class for sidecar resolvers. A resolver knows how to read one asset format and name the
## sibling files it references by URI — the files Godot's dependency graph cannot see.


## True if this resolver understands `path`.
func can_handle(_path: String) -> bool:
	return false


## Returns { "sidecars": PackedStringArray, "skipped": Array }.
## `sidecars` are existing paths, deduped, never including `path` itself.
## `skipped` entries are { "uri": String, "reason": String } for the report.
func collect(_path: String) -> Dictionary:
	return {"sidecars": PackedStringArray(), "skipped": []}
