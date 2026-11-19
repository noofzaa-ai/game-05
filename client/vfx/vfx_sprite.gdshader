shader_type spatial;
// Flat effect shapes drawn on a quad: glow, impact star, ink splat, ring, light beam, stun swirl,
// afterimage silhouette, crossed slashes, a jagged lightning bolt and a licking flame. The shape is a
// uniform (`mode`), so one compiled shader serves all of them. billboard: 0 = as placed, 1 = faces the
// camera, 2 = turns around the up axis only, 3 = turns around its own long (local y) axis to face the
// camera (a bolt stretched between two points).
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled, blend_mix;

#include "res://client/vfx/vfx_common.gdshaderinc"
#include "res://client/vfx/vfx_sprite_body.gdshaderinc"
