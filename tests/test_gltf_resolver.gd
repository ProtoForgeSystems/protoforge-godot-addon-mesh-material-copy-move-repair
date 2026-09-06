extends SceneTree
## Headless: GltfResolver.collect() against the URI cases spec §2 enumerates.

const Fixture := preload("res://addons/mesh_material_copy_move_repair/tests/fixture.gd")
const GltfResolver := preload("res://addons/mesh_material_copy_move_repair/gltf_resolver.gd")

var _failures := 0


func _check(ok: bool, name: String) -> void:
	if ok:
		print("  ok   %s" % name)
	else:
		_failures += 1
		print("  FAIL %s" % name)


func _reasons(got: Dictionary) -> String:
	var out := PackedStringArray()
	for s in got.skipped:
		out.append(s.reason)
	return ", ".join(out)


func _init() -> void:
	var base := Fixture.reset()
	var r := GltfResolver.new()

	_check(r.can_handle("res://a/b.gltf"), "handles .gltf")
	_check(r.can_handle("res://a/b.GLTF"), "handles .gltf case-insensitively")
	_check(r.can_handle("res://a/b.glb"), "handles .glb")
	_check(r.can_handle("res://a/b.GLB"), "handles .glb case-insensitively")
	_check(not r.can_handle("res://a/b.png"), "does not handle .png")

	# The ordinary case: one buffer, three textures, one of them named twice.
	Fixture.write_blob("plain/m.bin")
	Fixture.write_blob("plain/d.png")
	Fixture.write_blob("plain/n.png")
	var plain := Fixture.write_gltf("plain/m.gltf", ["m.bin"], ["d.png", "n.png", "d.png"])
	var got: Dictionary = r.collect(plain)
	_check(got.sidecars.size() == 3, "plain: three sidecars, deduped (got %d)" % got.sidecars.size())
	_check(got.sidecars.has(base.path_join("plain/m.bin")), "plain: buffer found")
	_check(got.sidecars.has(base.path_join("plain/d.png")), "plain: texture found")
	_check(not got.sidecars.has(plain), "plain: never includes itself")

	# Embedded buffer (GLB-style) and bufferView images have no uri at all.
	got = r.collect(Fixture.write_gltf("embed/m.gltf", [null], [null]))
	_check(got.sidecars.is_empty() and got.skipped.is_empty(), "no uri: nothing collected, nothing skipped")

	# data: URIs are inline, not files.
	got = r.collect(Fixture.write_gltf("inline/m.gltf", ["data:application/octet-stream;base64,AAAA"], []))
	_check(got.sidecars.is_empty() and got.skipped.is_empty(), "data: uri ignored silently")

	# Percent-encoded filename.
	Fixture.write_blob("pct/my texture.png")
	got = r.collect(Fixture.write_gltf("pct/m.gltf", [], ["my%20texture.png"]))
	_check(got.sidecars.has(base.path_join("pct/my texture.png")), "percent-encoded uri decoded")

	# ../ in a uri, resolving to a real sibling directory.
	Fixture.write_blob("rel/shared/t.png")
	got = r.collect(Fixture.write_gltf("rel/mesh/m.gltf", [], ["../shared/t.png"]))
	_check(got.sidecars.has(base.path_join("rel/shared/t.png")), "../ resolved against the gltf's dir")

	# ../ that climbs out of the project root entirely.
	got = r.collect(Fixture.write_gltf("esc/m.gltf", [], ["../../../../../../../../etc/passwd"]))
	_check(got.sidecars.is_empty(), "escaping uri not collected")
	_check(got.skipped.size() == 1 and got.skipped[0].reason.contains("outside"), "escaping uri reported (%s)" % _reasons(got))

	# An http uri is somebody else's problem.
	got = r.collect(Fixture.write_gltf("remote/m.gltf", [], ["https://example.com/t.png"]))
	_check(got.sidecars.is_empty() and got.skipped.size() == 1, "remote uri skipped")

	# Named but absent.
	got = r.collect(Fixture.write_gltf("missing/m.gltf", ["gone.bin"], []))
	_check(got.sidecars.is_empty(), "missing file not collected")
	_check(got.skipped.size() == 1 and got.skipped[0].reason.contains("missing"), "missing file reported (%s)" % _reasons(got))

	# Malformed and unreadable.
	got = r.collect(Fixture.write_raw("bad/m.gltf", "{ this is not json"))
	_check(got.sidecars.is_empty() and got.skipped.size() == 1, "malformed json yields no sidecars and one note")
	got = r.collect(base.path_join("nope/absent.gltf"))
	_check(got.sidecars.is_empty() and got.skipped.size() == 1, "unreadable gltf yields one note")

	# The URI base can differ from where the document lives: after a dock move the .gltf sits at
	# its new home while its sidecars are still at the old one.
	Fixture.write_blob("split/src/m.bin")
	var relocated := Fixture.write_gltf("split/dst/m.gltf", ["m.bin"], [])
	got = r.collect(relocated)
	_check(got.sidecars.is_empty(), "no override: the sidecar is not found at the document's new home")
	got = r.collect(relocated, base.path_join("split/src"))
	_check(got.sidecars.has(base.path_join("split/src/m.bin")), "uri_base_dir override finds the sidecar left behind")

	# A .glb is self-contained only by its exporter's choice. One that embeds everything yields
	# nothing, and the addon stays out of its way; one that names an external texture is exactly
	# as vulnerable as a .gltf, and must be seen.
	var embedded_glb := Fixture.write_glb("glb/embedded.glb", [null], [null])
	got = r.collect(embedded_glb)
	_check(got.sidecars.is_empty() and got.skipped.is_empty(), "an embedded .glb yields nothing, quietly")

	Fixture.write_blob("glb/skin.png")
	var external_glb := Fixture.write_glb("glb/external.glb", [null], ["skin.png"])
	got = r.collect(external_glb)
	_check(got.sidecars.has(base.path_join("glb/skin.png")), "a .glb's external texture is found")

	# Anything that is not a real container must be refused, not crash.
	got = r.collect(Fixture.write_raw("glb/garbage.glb", "this is not a GLB container at all"))
	_check(got.sidecars.is_empty() and got.skipped.size() == 1, "a malformed .glb is reported, not fatal")
	got = r.collect(Fixture.write_raw("glb/tiny.glb", "gl"))
	_check(got.sidecars.is_empty() and got.skipped.size() == 1, "a truncated .glb is reported, not fatal")

	Fixture.rm_rf(Fixture.DIR)
	print("gltf_resolver tests: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	quit(0 if _failures == 0 else 1)
