shader_type spatial;
// Additive twin of vfx_sprite.gdshader (same shapes and uniforms): light ADDS to the scene. For the bright cores of the
// violent skill looks (Boss 2026-11-19: additive glow allowed). A layer opts in with "glow": true in data/combat/vfx.json.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled, blend_add;

#include "res://client/vfx/vfx_common.gdshaderinc"
#include "res://client/vfx/vfx_sprite_body.gdshaderinc"
