shader_type spatial;
// Additive twin of vfx_burst.gdshader (same particles and uniforms): glowing sparks and embers for the violent skill
// looks. A layer opts in with "glow": true in data/combat/vfx.json.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled, blend_add, skip_vertex_transform;

#include "res://client/vfx/vfx_common.gdshaderinc"
#include "res://client/vfx/vfx_burst_body.gdshaderinc"
