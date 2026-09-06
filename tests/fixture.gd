extends RefCounted
## Test-only: builds throwaway glTF assets under user://, so fixtures never dirty the host project,
## never reach its .import pipeline, and never trip its uid checks.

const DIR := "user://sidecar_tests"


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
