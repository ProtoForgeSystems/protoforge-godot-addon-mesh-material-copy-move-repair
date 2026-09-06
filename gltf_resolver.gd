extends "res://addons/mesh_material_copy_move_repair/sidecar_resolver.gd"
## Reads a .gltf's or .glb's JSON document and names the sibling files it references by relative
## URI: the external buffer (.bin) and any external images. Godot's dependency graph cannot see
## these — they live in the glTF document, not in the .import — which is why moving a .gltf in the
## dock breaks it.
##
## .glb is handled too. Embedding is the exporter's CHOICE, not a property of the format: only
## buffers[0] (the binary chunk) is required to be embedded in a .glb -- any further buffer, and
## any image, may still legally carry an external uri. A .glb that does so is exactly as
## vulnerable to a bare dock move as a .gltf; a .glb that embeds everything (the common case)
## simply yields nothing here, and the addon stays out of its way.


func can_handle(path: String) -> bool:
	var ext := path.get_extension().to_lower()
	return ext == "gltf" or ext == "glb"


## Returns the glTF JSON document as text, or "" if the file is not a readable glTF.
##
## A .gltf IS the JSON. A .glb wraps it in a binary container: a 12-byte header (the "glTF"
## magic, a version, the total length) then chunks, the first of which must be the JSON. Reading
## it matters because a .glb is only self-contained by its exporter's CHOICE -- buffers[0] must
## be embedded, but any further buffer and any image may legally name an external file, and
## those are sidecars exactly like a .gltf's.
static func _read_document(path: String) -> String:
	if path.get_extension().to_lower() != "glb":
		return FileAccess.get_file_as_string(path)
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_length() < 20:
		return ""
	if f.get_buffer(4).get_string_from_ascii() != "glTF":
		return ""
	f.get_32()  # version
	f.get_32()  # total length
	var chunk_length := f.get_32()
	var chunk_type := f.get_32()
	if chunk_type != 0x4E4F534A:  # "JSON"
		return ""
	if chunk_length == 0 or chunk_length > f.get_length() - 20:
		return ""
	return f.get_buffer(chunk_length).get_string_from_utf8()


func collect(path: String, uri_base_dir: String = "") -> Dictionary:
	var out := {"sidecars": PackedStringArray(), "skipped": []}
	if not FileAccess.file_exists(path):
		out.skipped.append({"uri": path, "reason": "unreadable"})
		return out
	# JSON.parse_string() ERR_PRINTs on every failure; the instance API returns the same error
	# code silently. A malformed .gltf is a case this resolver handles by design, so it must not
	# spam the Output panel of every project that happens to contain one.
	var text := _read_document(path)
	var json := JSON.new()
	if text.is_empty() or json.parse(text) != OK or typeof(json.data) != TYPE_DICTIONARY:
		out.skipped.append({"uri": path, "reason": "malformed glTF JSON"})
		return out
	var parsed: Dictionary = json.data

	# Not always the document's own directory -- see the base class docstring.
	var base := uri_base_dir if not uri_base_dir.is_empty() else path.get_base_dir()
	var seen := {}
	for key in ["buffers", "images"]:
		var entries: Variant = parsed.get(key, [])
		if typeof(entries) != TYPE_ARRAY:
			continue
		for entry in entries:
			# No uri means the data is embedded (a GLB chunk, or an image in a bufferView).
			if typeof(entry) != TYPE_DICTIONARY or not entry.has("uri"):
				continue
			var uri := String(entry["uri"])
			if uri.begins_with("data:"):
				continue
			var resolved := _resolve(base, uri)
			if resolved.is_empty():
				out.skipped.append({"uri": uri, "reason": "resolves outside the project root"})
				continue
			if seen.has(resolved):
				continue
			seen[resolved] = true
			if not FileAccess.file_exists(resolved):
				out.skipped.append({"uri": uri, "reason": "missing file"})
				continue
			out.sidecars.append(resolved)
	return out


## Resolves a glTF URI against the document's directory. Returns "" for anything that is not a file
## under the same root the document lives in — a remote URL, or a path that climbs out of it.
## The root is taken from the document rather than hardcoded to res:// so the tests can run
## entirely under user:// without touching the host project.
##
## Does its own "../" collapsing with an explicit segment walk rather than String.simplify_path().
## Measured (2026-09-06): simplify_path() does not treat "user://"/"res://" as a hard boundary --
## it clamps excess ".." segments instead of failing, so a URI with enough ".." climbs past the
## root and lands back inside it. "user://mesh_material_cmr_tests/esc".path_join("../../../../../../../../etc/passwd")
## .simplify_path() returns "user://etc/passwd", which still passes begins_with(root) and would
## silently resolve an escaping URI instead of rejecting it.
static func _resolve(base_dir: String, uri: String) -> String:
	var root := "res://"
	if base_dir.begins_with("user://"):
		root = "user://"
	elif not base_dir.begins_with("res://"):
		return ""
	var decoded := uri.uri_decode()
	if decoded.contains("://"):
		return decoded if decoded.begins_with(root) else ""
	var joined := base_dir.path_join(decoded)
	var rest := joined.substr(root.length())
	var stack: Array[String] = []
	for part in rest.split("/"):
		if part.is_empty() or part == ".":
			continue
		elif part == "..":
			if stack.is_empty():
				return ""
			stack.pop_back()
		else:
			stack.append(part)
	return root + "/".join(stack)
