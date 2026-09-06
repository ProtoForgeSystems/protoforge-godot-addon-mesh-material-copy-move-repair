extends SceneTree
## Headless: the whole move path against the arrangement a real FileSystem-dock move leaves —
## the .gltf already at its destination, its sidecars still behind. Nothing else covers the
## seam between the resolver's output and the plan's assumptions, which is where the addon was
## silently doing nothing at all.

const Fixture := preload("res://addons/mesh_material_copy_move_repair/tests/fixture.gd")
const GltfResolver := preload("res://addons/mesh_material_copy_move_repair/gltf_resolver.gd")
const Plan := preload("res://addons/mesh_material_copy_move_repair/plan.gd")
const Executor := preload("res://addons/mesh_material_copy_move_repair/executor.gd")

var _failures := 0


func _check(ok: bool, name: String) -> void:
	if ok:
		print("  ok   %s" % name)
	else:
		_failures += 1
		print("  FAIL %s" % name)


func _nothing_shared(_p: String) -> bool:
	return false


func _init() -> void:
	var base := Fixture.reset()
	var src := base.path_join("kit")
	var dst := base.path_join("dest")

	# Exactly what the dock leaves behind: the .gltf moved, the sidecars not.
	Fixture.write_blob("kit/m.bin")
	Fixture.write_blob("kit/textures/diffuse.png")
	var moved := Fixture.write_gltf("dest/m.gltf", ["m.bin"], ["textures/diffuse.png"])

	# The dock moves a .gltf together with its .import, so the primary HAS one at its new home,
	# carrying a stale artifact path and a uid that other scenes still reference. Reconciling it
	# is the whole reason the primary appears in the plan at all.
	Fixture.write_raw("dest/m.gltf.import", "[remap]\n\nimporter=\"scene\"\nuid=\"uid://e2e1\"\npath=\"user://stale.scn\"\n\n[deps]\n\nsource_file=\"%s\"\ndest_files=[\"user://stale.scn\"]\n\n[params]\n\nnodes/root_scale=1.0\n" % src.path_join("m.gltf"))

	var found: Dictionary = GltfResolver.new().collect(moved, src)
	_check(found.sidecars.size() == 2, "resolver finds both sidecars at the old home (got %d)" % found.sidecars.size())

	var plan: Dictionary = Plan.build(Plan.Mode.MOVE, src.path_join("m.gltf"), moved, found.sidecars, _nothing_shared)
	_check(not plan.actions.is_empty(), "the move produces actions at all")
	var report: Array = Executor.apply(plan.actions)

	_check(FileAccess.file_exists(dst.path_join("m.bin")), "the .bin followed the asset")
	_check(FileAccess.file_exists(dst.path_join("textures/diffuse.png")), "the nested texture kept its subdirectory")
	_check(not FileAccess.file_exists(src.path_join("m.bin")), "the moved .bin is gone from the old home")
	_check(report.size() == 3, "one report line per action (got %d)" % report.size())

	# The primary's own .import is reconciled in place: uid preserved so existing references
	# keep resolving, stale artifact keys dropped, tuned parameters untouched.
	var primary_import := FileAccess.get_file_as_string(dst.path_join("m.gltf.import"))
	_check(primary_import.contains("uid://e2e1"), "the moved primary keeps its uid")
	_check(primary_import.contains('source_file="%s"' % moved), "the primary's source_file is repointed")
	_check(not primary_import.contains("path="), "the primary's stale artifact keys are dropped")
	_check(primary_import.contains("nodes/root_scale=1.0"), "the primary's tuned params survive")

	Fixture.rm_rf(Fixture.DIR)
	print("move_end_to_end tests: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	quit(0 if _failures == 0 else 1)
