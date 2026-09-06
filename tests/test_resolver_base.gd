extends SceneTree
## Headless: the resolver base class contract. Every resolver returns the same shape.

const Resolver := preload("res://addons/sidecar/sidecar_resolver.gd")

var _failures := 0


func _check(ok: bool, name: String) -> void:
	if ok:
		print("  ok   %s" % name)
	else:
		_failures += 1
		print("  FAIL %s" % name)


func _init() -> void:
	var r := Resolver.new()
	_check(r.can_handle("res://anything.gltf") == false, "base can_handle is false")
	var got: Dictionary = r.collect("res://anything.gltf")
	_check(got.has("sidecars") and got.has("skipped"), "collect returns both keys")
	_check(got.sidecars is PackedStringArray and got.sidecars.is_empty(), "base sidecars empty")
	_check(got.skipped is Array and got.skipped.is_empty(), "base skipped empty")
	print("resolver_base tests: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	quit(0 if _failures == 0 else 1)
