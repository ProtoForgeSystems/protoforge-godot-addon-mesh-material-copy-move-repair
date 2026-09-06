extends RefCounted
## Rewrites a .import file so it belongs to a relocated or duplicated asset.
##
## Two rules carry all the risk:
##   MOVE keeps the uid and `type=` — scenes and resources elsewhere reference this file by uid,
##   and the uid still resolves to the artifact that already exists.
##   COPY drops both, so Godot mints a fresh uid and a fresh `type=` on reimport. Two files
##   sharing a uid makes the engine load whichever it resolves first, silently, and rewrite paths
##   to match on the next save. A copy also has no imported artifact yet, so leaving `type=` in
##   place declares a known resource type the editor cannot load — it logs "Failed loading
##   resource" for it until the reimport lands. `importer=` is left alone either way, so Godot
##   still knows how to (re)import the file.
## Both drop the artifact keys (`path`, `path.*`, `dest_files`), because the imported artifact's
## filename embeds an md5 of the source path; a stale one aims the asset at another file's artifact.
## Everything else is preserved verbatim, which is the point of editing rather than deleting:
## compression settings, retarget blocks and LOD parameters survive the move.

const _DROPPED_PREFIXES := ["path=", "path.", "dest_files="]


static func reconcile(text: String, old_source: String, new_source: String, keep_uid: bool) -> String:
	# Every path in a .import is quoted, so the replacement is anchored to the quotes. A bare
	# substring replace would also rewrite any path that merely SHARES A PREFIX with the one
	# being moved -- and `roughness/src_normal` legitimately names a different file from
	# `source_file`, so a sibling's reference would be silently repointed at a file that is
	# not moving.
	var quoted_old := '"%s"' % old_source
	var quoted_new := '"%s"' % new_source
	var out := PackedStringArray()
	for line in text.split("\n"):
		var stripped := line.strip_edges(true, false)
		if _is_dropped(stripped):
			continue
		if not keep_uid and (stripped.begins_with("uid=") or stripped.begins_with("type=")):
			# A copy has no imported artifact yet. Dropping the uid alone leaves the .import
			# still declaring a resource of a known type that cannot be loaded, and the editor
			# logs "Failed loading resource" for each one before the reimport lands. A move does
			# not hit this: it keeps its uid, which still resolves to the old artifact.
			# Godot regenerates type= from importer= on import (measured, 2026-09-06).
			continue
		out.append(line.replace(quoted_old, quoted_new))
	return "\n".join(out)


static func _is_dropped(stripped: String) -> bool:
	for prefix in _DROPPED_PREFIXES:
		if stripped.begins_with(prefix):
			return true
	return false
