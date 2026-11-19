shader_type spatial;
// A burst of sparks, ink drops, dust puffs or motes in ONE draw call: the mesh holds up to 32
// quads, each with its own random numbers baked in, and the vertex shader moves them (speed,
// spread cone, gravity, drag) from `progress`. No particle simulation on the CPU.
// style: 0 = streaks stretched along their motion (sparks), 1 = soft puffs that grow (dust, ink),
// 2 = small round glints (motes).
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled, blend_mix, skip_vertex_transform;

#include "res://client/vfx/vfx_common.gdshaderinc"
#include "res://client/vfx/vfx_burst_body.gdshaderinc"
