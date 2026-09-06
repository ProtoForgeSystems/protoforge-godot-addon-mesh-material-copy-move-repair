extends RefCounted
## Rewrites a .import file so it belongs to a relocated or duplicated asset.
##
## Two rules carry all the risk:
##   MOVE keeps the uid — scenes and resources elsewhere reference this file by uid.
##   COPY drops it, so Godot mints a fresh one. Two files sharing a uid makes the engine load
##   whichever it resolves first, silently, and rewrite paths to match on the next save.
## Both drop the artifact keys (`path`, `path.*`, `dest_files`), because the imported artifact's
## filename embeds an md5 of the source path; a stale one aims the asset at another file's artifact.
## Everything else is preserved verbatim, which is the point of editing rather than deleting:
## compression settings, retarget blocks and LOD parameters survive the move.

const _DROPPED_PREFIXES := ["path=", "path.", "dest_files="]


static func reconcile(text: String, old_source: String, new_source: String, keep_uid: bool) -> String:
	var out := PackedStringArray()
	for line in text.split("\n"):
		var stripped := line.strip_edges(true, false)
		if _is_dropped(stripped):
			continue
		if not keep_uid and stripped.begins_with("uid="):
			continue
		out.append(line.replace(old_source, new_source))
	return "\n".join(out)


static func _is_dropped(stripped: String) -> bool:
	for prefix in _DROPPED_PREFIXES:
		if stripped.begins_with(prefix):
			return true
	return false
