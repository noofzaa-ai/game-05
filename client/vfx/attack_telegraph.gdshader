shader_type spatial;
// The ground warning of a monster move that is winding up (Boss 2026-11-04: "a red area in the
// direction it is about to release, with a gauge that flows to show it is about to land"). Same
// language as area_telegraph.gdshader (ink under a bright rim, a fill that reaches the end at the
// moment of release, faster pulse near the end), in danger red, in two shapes:
//   shape 0 = lane: a flat quad laid along the attack (UV.x 0 = at the monster, 1 = far end).
//             The gauge flows from the monster to the far end; chevrons slide the same way so the
//             direction reads even at the very start. far_width < 1 tapers it into a fan.
//   shape 1 = circle: a blow all around the monster or a spot about to be hit; fills from the center.
// One quad per warning; only uniforms change per frame (no mesh rebuilds).
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled, blend_mix;

#include "res://client/vfx/vfx_common.gdshaderinc"

uniform vec4 color : source_color = vec4(1.0, 0.16, 0.08, 1.0);
uniform vec4 ink_color : source_color = vec4(0.10, 0.01, 0.01, 1.0);
uniform int shape = 0;
uniform vec2 size_m = vec2(2.0, 2.0);   // the quad's size in meters (length, width), for even rims
uniform float near_width = 1.0;          // lane width at the monster, as a fraction of size_m.y
uniform float far_width = 1.0;           // lane width at the far end, as a fraction of size_m.y
uniform float progress = 0.0;
uniform float time = 0.0;
uniform float opacity = 1.0;
uniform float drawn = 0.0;  // 1 = ink-wash look (client/vfx/ink_vfx.gd via draw_style.gd): grain-broken edges, flat glazes

void fragment() {
	float t = clamp(progress, 0.0, 1.0);
	float ease = t * t * (3.0 - 2.0 * t);
	float pulse = 0.7 + 0.3 * sin(time * mix(7.0, 26.0, t));
	float rim_m = 0.07;
	float inside;
	float edge_m;      // distance to the outline in meters (0 at the rim)
	float along;       // 0 at the source of the attack -> 1 at where it ends (the gauge axis)
	float chevrons = 0.0;
	if (shape == 1) {
		vec2 p = UV * 2.0 - 1.0;
		float r = length(p);
		float radius_m = size_m.x * 0.5;
		inside = step(r, 1.0);
		edge_m = (1.0 - r) * radius_m;
		along = r;
		float a = atan(p.y, p.x);
		// Ticks around the rim, turning (as on the hex circle) so it never looks frozen.
		chevrons = step(0.6, fract((a / 6.2831853) * 14.0 - time * 0.35))
			* smoothstep(0.12, 0.04, abs(edge_m - 0.22));
	} else {
		float u = UV.x;
		float v = abs(UV.y * 2.0 - 1.0);
		float half_w = mix(near_width, far_width, u);
		inside = step(v, half_w) * step(0.0, u) * step(u, 1.0);
		float side_m = (half_w - v) * size_m.y * 0.5;
		float end_m = min(u, 1.0 - u) * size_m.x;
		edge_m = min(side_m, end_m);
		along = u;
		// Chevrons pointing down the lane and sliding along it.
		float d = u * size_m.x - (v / max(half_w, 0.001)) * 0.45;
		float stripe = fract(d / 1.1 - time * 1.6);
		chevrons = smoothstep(0.0, 0.08, stripe) * smoothstep(0.32, 0.22, stripe)
			* step(0.18, side_m) * step(0.15, end_m);
	}
	float rim = smoothstep(rim_m, 0.0, abs(edge_m - rim_m));
	float rim_ink = smoothstep(rim_m * 2.6, rim_m * 0.8, edge_m);
	// The gauge: the filled part is brighter, with a hot front where it is up to now.
	float front_at = mix(0.02, 1.0, ease);
	float filled = smoothstep(front_at + 0.012, front_at - 0.012, along);
	float front = smoothstep(0.035, 0.0, abs(along - front_at)) * step(along, 1.0) * (1.0 - step(0.999, ease));
	float base = 0.16;
	float fill = filled * (0.28 + 0.22 * ease);
	float bright = clamp(rim + front + chevrons * 0.6 + fill * 1.6, 0.0, 1.0);
	vec3 hot = mix(color.rgb, vec3(1.0, 0.85, 0.6), front * 0.7);
	vec3 rgb = mix(ink_color.rgb, hot, bright);
	float alpha = max(max(rim * pulse, rim_ink * 0.7), max(front, max(base + fill, chevrons * (0.35 + 0.25 * (1.0 - filled)))));
	alpha = clamp(alpha, 0.0, 1.0) * inside * opacity * color.a;
	if (drawn > 0.5) {
		// Readability first: the danger red stays saturated (no tone step), only the paint edges and glazes change.
		vec4 o = vfx_ink(rgb, alpha, UV, UV * size_m * 2.2, ink_color.rgb);
		rgb = mix(rgb, o.rgb, 0.5);
		alpha = o.a;
	}
	ALBEDO = rgb;
	ALPHA = alpha;
}
