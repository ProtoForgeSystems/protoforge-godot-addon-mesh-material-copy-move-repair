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
	# An asset with no sidecars is not this addon's business — a .glb, or a fully embedded glTF.
	if sidecars.is_empty():
		return out

	var dest_dir := primary_to.get_base_dir()

	match mode:
		Mode.MOVE:
			# The dock already relocated the primary; only its poisoned .import needs fixing.
			out.actions.append(_action(Op.RECONCILE, primary_from, primary_to, true))
		Mode.COPY:
			out.actions.append(_action(Op.COPY, primary_from, primary_to, false))
		Mode.REPAIR:
			out.actions.append(_action(Op.RECONCILE, primary_from, primary_from, true))

	for s in sidecars:
		# Sidecars keep their filenames and land beside the primary, so the glTF's relative
		# URIs stay valid and never need rewriting.
		var to := dest_dir.path_join(s.get_file())
		match mode:
			Mode.REPAIR:
				out.actions.append(_action(Op.RECONCILE, s, s, true))
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


static func _action(op: int, from: String, to: String, keep_uid: bool) -> Dictionary:
	return {"op": op, "from": from, "to": to, "keep_uid": keep_uid}
