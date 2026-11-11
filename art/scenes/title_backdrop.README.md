# Title backdrop GLB

`title_backdrop.glb` is a static export of `client/title_backdrop.gd`.

Rebuild from the project root:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --log-file /tmp/zorx-title-export.log --path . --script res://tools/export/title_backdrop_glb.gd
```

Includes scene geometry, 144 expanded MultiMesh prop instances, camera and supported lights/materials. Shader sky/moon/cloud/mist surfaces use approximate baked textures for portable glTF materials; their appearance is not identical to Godot. The screen-space menu shade is omitted.

CPU particles (flames, embers, fireflies), WorldEnvironment settings, camera drift and script-driven animation are not included. The campfire logs/rocks remain. This is a static scenery asset, not a replacement for the animated title screen. The original script and title scene are unchanged.
