extends RefCounted
## Answers "does any other asset reference this sidecar?" — the check that stops a move from
## breaking every asset left behind. Walks EditorFileSystem's in-memory tree rather than the disk,
## filtered to files a resolver claims, and only when an asset is actually being moved.


static func make(resolvers: Array, root: EditorFileSystemDirectory, exclude: String) -> Callable:
	var owners := {}
	_walk(resolvers, root, exclude, owners)
	return func(path: String) -> bool: return owners.has(path)


static func _walk(resolvers: Array, dir: EditorFileSystemDirectory, exclude: String, owners: Dictionary) -> void:
	for i in dir.get_file_count():
		var path := dir.get_file_path(i)
		if path == exclude:
			continue
		for r in resolvers:
			if not r.can_handle(path):
				continue
			for s in r.collect(path).sidecars:
				owners[s] = true
	for i in dir.get_subdir_count():
		_walk(resolvers, dir.get_subdir(i), exclude, owners)
