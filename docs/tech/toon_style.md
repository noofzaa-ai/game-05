# Global Toon presentation

Boss requested 2026-10-23: Toon-shaded world with OutlineEffect-like silhouettes, width .005 and fine hair .0015–.002.

Godot uses BaseMaterial3D DIFFUSE_TOON / SPECULAR_TOON and the existing culled outline shader, not the Three.js OutlineEffect class. An autoload prepares newly entering meshes with deferred work, not a per-frame world traversal. Original albedo/textures/UVs remain intact. Shader-driven effects and unshaded objects retain their authored appearance. Opaque geometry gets silhouettes; transparent smoke/glows do not.

Widths: ordinary meshes .005; hair .002; named fringe/strand/lock pieces .0015. Set mesh metadata toon_outline_width for exact asset-specific overrides. These are mesh-space units (meters before model transforms), not screen-space normalized Three.js units. Minimum pixel clamp is zero so fine hair can actually be thinner. Existing InkOutline children are reused instead of adding a second outline.

Local implementation only: no deployment. Visual/device acceptance remains pending. Outline passes add rendering work; FPS must be reviewed on the target mobile devices before release. Runtime-added geometry whose materials are assigned later than the deferred preparation may need an explicit refresh hook in its builder.

Editor import completed with no script parse errors. Sandbox prevented saving user-wide editor settings; no automated tests were run.
