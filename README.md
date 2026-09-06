# ProtoForge Sidecar

A Godot 4.4+ editor addon that moves and copies `.gltf` files together with
the `.bin` and textures they depend on.

## The problem

A `.gltf` names its `.bin` and its textures inside its own JSON, as relative
URIs — Godot's dependency graph never parses that JSON, so it cannot see
those files at all. Drag the `.gltf` alone in the FileSystem dock and it
moves alone, leaving its sidecars behind and the asset broken. Putting the
missing file back does not fix it either: the failed import has already
written a poisoned `.import`, and nothing invalidates that on its own.

This is an open gap in the engine, not an opinion — see
[godotengine/godot#43043](https://github.com/godotengine/godot/issues/43043),
[#111554](https://github.com/godotengine/godot/issues/111554), and
[#85177](https://github.com/godotengine/godot/issues/85177).

## Install

**From the Asset Library:** search for "ProtoForge Sidecar" in Godot's
AssetLib tab and install it directly into your project.

**Manually:** clone or download this repository into `res://addons/sidecar`
in your project.

Then enable it under **Project > Project Settings > Plugins**.

## Quick start

Drag a `.gltf` in the FileSystem dock, anywhere you'd normally drag a file.
That's the whole feature — its `.bin` and textures follow, and nothing else
about the gesture changes.

Two more actions live on the file's right-click menu:

- **Copy with dependencies…** — copies the asset and everything it
  references, minting fresh uids so no two files on disk ever share one.
- **Repair sidecars** — fixes an asset a past move already broke.

## Features

- Dependencies follow a plain drag — no new gesture to learn.
- Copy with dependencies, uid-safe.
- Repair an already-broken asset.
- A sidecar shared with another asset is copied rather than moved, so
  relocating one mesh's texture can't break every other mesh using it.
- Zero dependencies, zero configuration.

## How it works

Sidecar parses the glTF's own `buffers` and `images` arrays for their URIs,
carries the files they name alongside the primary asset, and rewrites each
touched `.import` so the editor's reimport succeeds instead of poisoning
itself. A move preserves each file's existing uid, so anything already
referencing it keeps resolving; a copy mints a fresh uid instead, so the
original and the copy never collide.

**The surprising case:** if another asset also references a sidecar, that
sidecar is *copied*, not moved, even on a move of the primary asset. Moving
a texture that four other meshes use would silently break all four just to
satisfy the one you dragged.

**Repair's precondition:** Repair fixes a poisoned `.import` left by a bad
move. It does not fetch anything that's missing. If the `.bin` or a texture
is actually gone, put it back beside the `.gltf` first — then run Repair.

## Known limitations

- `.glb` embeds its buffers and images, so it has no sidecars and is
  ignored by design.
- `.obj` / `.mtl` is not supported yet — the resolver interface exists for
  it, but no implementation is wired in.
- Folder moves aren't hooked: dragging a folder carries the sidecars along
  for free (the OS move does that), but the `.gltf`'s `.import` is not
  reconciled — run Repair on it afterward.
- No undo. Every file the addon touches is listed in the Output panel.
- A sidecar that lives outside the asset's own directory (a `../` URI) is
  left where it is, and the report says so — relocating it would change
  what the URI resolves to.
- Godot 4.4+.

## For contributors

Toggling the plugin off and on in Project Settings does not fully reload
it. `plugin.gd` itself is re-read by path, but every script it `preload`s
comes back from Godot's resource cache, so an edit to `import_file.gd` or
`executor.gd` stays stale until the editor restarts. A fix two `preload`s
deep can look like it didn't work for exactly this reason — restart the
editor before concluding it didn't.

## For ProtoForge repos

Development happens in `ProtoForgeSystems/unreal-assets`, which carries the
test suite (`tests/`, `run_tests.sh`) against real glTF fixtures. Changes
are made there, committed and pushed to this repo, and consuming repos then
bump their submodule pointer — this addon takes no local changes anywhere
downstream of here.

Mount as a git submodule at `addons/sidecar` (or `game/addons/sidecar` when
the Godot project is nested), then enable `res://addons/sidecar/plugin.cfg`
under `[editor_plugins]` in `project.godot`.

## License

MIT — see [LICENSE](LICENSE).
