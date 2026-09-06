extends RefCounted
## Turns "this asset moved / is being copied / is broken" into a list of file actions, as data.
## Pure: no filesystem access, no editor API. The editor-side executor performs what this decides,
## which is what makes the two risky rules testable headlessly.

enum Mode { MOVE, COPY, REPAIR }
enum Op { MOVE, COPY, RECONCILE }


static func build(
	mode: int,
	primary_from: String,
	primary_to: String,
	sidecars: PackedStringArray,
	is_shared: Callable
) -> Dictionary:
	var out := {"actions": [], "notes": []}
	# An asset with no sidecars is not this addon's business on a MOVE (the dock already moved
	# it) or a REPAIR (there is nothing to reconcile) — but a COPY was explicitly asked for, and
	# copying nothing is not an answer. A self-contained .glb is the common case here.
	if sidecars.is_empty() and mode != Mode.COPY:
		return out

	var dest_dir := primary_to.get_base_dir()
	var from_dir := primary_from.get_base_dir()

	match mode:
		Mode.MOVE:
			# The dock already relocated the primary; only its poisoned .import needs fixing.
			out.actions.append(_action(Op.RECONCILE, primary_from, primary_to, true, true))
		Mode.COPY:
			out.actions.append(_action(Op.COPY, primary_from, primary_to, false, true))
		Mode.REPAIR:
			out.actions.append(_action(Op.RECONCILE, primary_from, primary_from, true, true))

	for s in sidecars:
		# Repair moves nothing, so it needs no destination at all.
		if mode == Mode.REPAIR:
			out.actions.append(_action(Op.RECONCILE, s, s, true))
			continue
		# Sidecars keep their path RELATIVE TO THE ASSET, so a texture in a textures/ subfolder
		# lands in textures/ at the destination and the glTF's relative URI still resolves.
		# Flattening to get_file() breaks the asset -- and on a move it then deletes the only
		# copy that could have repaired it.
		var rel := _relative(from_dir, s)
		if rel.is_empty():
			# A "../" URI: the file lives outside the asset's own directory, and relocating it
			# would change what that URI resolves to. Leave it where it is and say so.
			out.notes.append("%s is outside %s — left in place" % [s, from_dir])
			continue
		var to := dest_dir.path_join(rel)
		match mode:
			Mode.COPY:
				out.actions.append(_action(Op.COPY, s, to, false))
			Mode.MOVE:
				if is_shared.call(s):
					# Moving this would break every other asset that references it.
					out.actions.append(_action(Op.COPY, s, to, false))
					out.notes.append("%s is shared with another asset — copied instead of moved" % s.get_file())
				else:
					out.actions.append(_action(Op.MOVE, s, to, true))
	return out


static func _action(op: int, from: String, to: String, keep_uid: bool, primary := false) -> Dictionary:
	return {"op": op, "from": from, "to": to, "keep_uid": keep_uid, "primary": primary}


## A sidecar's path relative to the asset's own directory, or "" when it lives outside it.
static func _relative(from_dir: String, path: String) -> String:
	var prefix := from_dir if from_dir.ends_with("/") else from_dir + "/"
	return path.substr(prefix.length()) if path.begins_with(prefix) else ""
