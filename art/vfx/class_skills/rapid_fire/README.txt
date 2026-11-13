daiyooo - VFX Studio / Godot 4 local delivery

Open effect.tscn after Godot finishes importing effect.glb. Instance this scene in your own scene. play_effect() restarts the single effect animation; stop_effect() stops it. Buff recipes loop by default; other recipes play once. free_on_finish is opt-in. Nothing edits project.godot.

Coordinates: right-handed Y-up, meters and seconds; asset forward +Z. Anchor "world" is metadata only: attach the generated Node3D to your own socket/character/world position. No root movement, gameplay damage or terrain collision is supplied. Recipe remains editable JSON.

GLB uses the Studio export pipeline: embedded RGBA textures, 8 lifetime phases and sampled particle transforms. Native alpha blending, additive appearance, Bloom and camera-facing particles differ from the browser reference. Test your lighting, camera and target Godot renderer. Textures are embedded; no remote asset connection is needed. preview.png shows the browser reference, not a screenshot of Godot.

Glow in Godot: the browser preview uses Bloom. For a similar look enable glow on your WorldEnvironment (Environment > Glow: Enabled, Blend Mode Additive or Screen, Intensity about 0.8-1.2, Bloom about 0.1-0.3, HDR Threshold about 0.9-1.0) and use the Forward+ or Mobile renderer; tune per scene. Native colours and brightness still differ from the preview.

The static effect_player.gd script is delivered for review and normal Godot use. MCP does not execute scripts in your project or change project settings.
