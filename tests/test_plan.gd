extends SceneTree
## Headless: the move/copy/repair rules, including the shared-sidecar rule that keeps a move from
## breaking the assets it leaves behind.

const Plan := preload("res://addons/sidecar/plan.gd")

var _failures := 0


func _check(ok: bool, name: String) -> void:
	if ok:
		print("  ok   %s" % name)
	else:
		_failures += 1
		print("  FAIL %s" % name)


func _find(actions: Array, from: String) -> Dictionary:
	for a in actions:
		if a.from == from:
			return a
	return {}


func _nothing_shared(_p: String) -> bool:
	return false


func _texture_shared(p: String) -> bool:
	return p.ends_with("shared.png")


func _init() -> void:
	var sidecars := PackedStringArray(["res://kit/m.bin", "res://kit/own.png", "res://kit/shared.png"])

	# MOVE, nothing shared.
	var got: Dictionary = Plan.build(Plan.Mode.MOVE, "res://kit/m.gltf", "res://dest/m.gltf", sidecars, _nothing_shared)
	_check(got.actions.size() == 4, "move: primary plus three sidecars (got %d)" % got.actions.size())
	var primary: Dictionary = _find(got.actions, "res://kit/m.gltf")
	_check(primary.op == Plan.Op.RECONCILE, "move: primary is reconcile-only, the dock already moved it")
	_check(primary.to == "res://dest/m.gltf", "move: primary reconciles at its new path")
	_check(primary.keep_uid, "move: primary keeps its uid")
	var bin: Dictionary = _find(got.actions, "res://kit/m.bin")
	_check(bin.op == Plan.Op.MOVE, "move: unshared sidecar moves")
	_check(bin.to == "res://dest/m.bin", "move: sidecar lands beside the primary, same filename")
	_check(bin.keep_uid, "move: moved sidecar keeps its uid")

	# MOVE with a shared texture.
	got = Plan.build(Plan.Mode.MOVE, "res://kit/m.gltf", "res://dest/m.gltf", sidecars, _texture_shared)
	var shared: Dictionary = _find(got.actions, "res://kit/shared.png")
	_check(shared.op == Plan.Op.COPY, "move: shared sidecar is copied, not moved")
	_check(not shared.keep_uid, "move: the copy of a shared sidecar gets a fresh uid")
	_check(_find(got.actions, "res://kit/own.png").op == Plan.Op.MOVE, "move: unshared sidecar still moves")
	var mentioned := false
	for n in got.notes:
		if n.contains("shared.png"):
			mentioned = true
	_check(mentioned, "move: the shared sidecar is named in the notes")

	# COPY: everything copies, nothing keeps a uid.
	got = Plan.build(Plan.Mode.COPY, "res://kit/m.gltf", "res://dest/m.gltf", sidecars, _texture_shared)
	_check(got.actions.size() == 4, "copy: primary plus three sidecars")
	var all_copy := true
	for a in got.actions:
		if a.op != Plan.Op.COPY or a.keep_uid:
			all_copy = false
	_check(all_copy, "copy: every action is a fresh-uid copy, shared or not")

	# REPAIR: nothing moves, everything is reconciled where it stands.
	got = Plan.build(Plan.Mode.REPAIR, "res://kit/m.gltf", "res://kit/m.gltf", sidecars, _texture_shared)
	var all_repair := true
	for a in got.actions:
		if a.op != Plan.Op.RECONCILE or a.from != a.to or not a.keep_uid:
			all_repair = false
	_check(all_repair, "repair: every action reconciles in place and keeps its uid")

	# No sidecars at all — a .glb, or a glTF with everything embedded.
	got = Plan.build(Plan.Mode.MOVE, "res://kit/m.gltf", "res://dest/m.gltf", PackedStringArray(), _nothing_shared)
	_check(got.actions.is_empty(), "no sidecars: no actions at all, the addon stays out of the way")

	# A sidecar in a subdirectory keeps its subpath, or the moved asset's relative URI stops
	# resolving -- and the move then deletes the only copy that could have repaired it.
	var nested := PackedStringArray(["res://kit/textures/diffuse.png"])
	got = Plan.build(Plan.Mode.MOVE, "res://kit/m.gltf", "res://dest/m.gltf", nested, _nothing_shared)
	_check(_find(got.actions, "res://kit/textures/diffuse.png").to == "res://dest/textures/diffuse.png", "a sidecar's subdirectory is preserved")

	# A sidecar outside the asset's own directory (a "../" URI) is left where it is.
	var outside := PackedStringArray(["res://shared/t.png"])
	got = Plan.build(Plan.Mode.MOVE, "res://kit/m.gltf", "res://dest/m.gltf", outside, _nothing_shared)
	_check(_find(got.actions, "res://shared/t.png").is_empty(), "a sidecar outside the asset's dir is not relocated")
	var noted := false
	for n in got.notes:
		if n.contains("outside"):
			noted = true
	_check(noted, "leaving it in place is reported")

	# Repair still reconciles a sidecar that lives outside the asset's directory.
	got = Plan.build(Plan.Mode.REPAIR, "res://kit/m.gltf", "res://kit/m.gltf", outside, _nothing_shared)
	_check(_find(got.actions, "res://shared/t.png").op == Plan.Op.RECONCILE, "repair reconciles an outside sidecar in place")

	print("plan tests: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	quit(0 if _failures == 0 else 1)
