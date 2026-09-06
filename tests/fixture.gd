extends RefCounted
## Test-only: builds throwaway glTF assets under user://, so fixtures never dirty the host project,
## never reach its .import pipeline, and never trip its uid checks.

const DIR := "user://mesh_material_cmr_tests"


static func reset() -> String:
	rm_rf(DIR)
	DirAccess.make_dir_recursive_absolute(DIR)
	return DIR


static func write_raw(rel: String, text: String) -> String:
	var path := DIR.path_join(rel)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	return path


static func write_blob(rel: String) -> String:
	return write_raw(rel, "not really binary, but it exists")


static func write_gltf(rel: String, buffer_uris: Array, image_uris: Array) -> String:
	var doc := {"asset": {"version": "2.0"}, "buffers": [], "images": []}
	for u in buffer_uris:
		doc.buffers.append({} if u == null else {"uri": u})
	for u in image_uris:
		doc.images.append({} if u == null else {"uri": u})
	return write_raw(rel, JSON.stringify(doc))


static func write_glb(rel: String, buffer_uris: Array, image_uris: Array) -> String:
	var doc := {"asset": {"version": "2.0"}, "buffers": [], "images": []}
	for u in buffer_uris:
		doc.buffers.append({} if u == null else {"uri": u})
	for u in image_uris:
		doc.images.append({} if u == null else {"uri": u})
	var json := JSON.stringify(doc).to_utf8_buffer()
	while json.size() % 4 != 0:
		json.append(0x20)
	var out := PackedByteArray()
	out.append_array("glTF".to_ascii_buffer())
	out.append_array(_u32(2))
	out.append_array(_u32(12 + 8 + json.size()))
	out.append_array(_u32(json.size()))
	out.append_array(_u32(0x4E4F534A))
	out.append_array(json)
	var path := DIR.path_join(rel)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(out)
	f.close()
	return path


static func _u32(v: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(4)
	b.encode_u32(0, v)
	return b


static func rm_rf(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var d := DirAccess.open(path)
	d.include_hidden = true
	for f in d.get_files():
		DirAccess.remove_absolute(path.path_join(f))
	for sub in d.get_directories():
		rm_rf(path.path_join(sub))
	DirAccess.remove_absolute(path)
