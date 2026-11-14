shader_type spatial;
// A brush stroke that follows a swing: the bright head travels along the stroke (UV.x 0 -> 1) and the
// tail thins out behind it like a dry brush, with a dark ink rim around a colored core.
// One material per pooled node; everything that changes is a uniform, so this compiles once.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled, blend_mix;

#include "res://client/vfx/vfx_common.gdshaderinc"

uniform vec4 color : source_color = vec4(1.0, 0.6, 0.2, 1.0);
uniform vec4 ink_color : source_color = vec4(0.06, 0.05, 0.08, 1.0);
uniform float ink = 0.6;  // 0 = pure color, 1 = a dark ink rim around a thin colored core
uniform float progress = 0.0;  // 0..1 over the effect's life
uniform float sweep = 0.5;  // part of the life the head needs to travel the whole stroke
uniform float tail = 0.7;  // how long the visible tail is (fraction of the stroke)
uniform float seed = 0.0;
uniform float opacity = 1.0;
uniform float drawn = 0.0;  // 1 = ink-wash look (client/vfx/ink_vfx.gd, graphics setting drawn_style)

void fragment() {
	float head = clamp(progress / max(sweep, 0.001), 0.0, 1.0);
	float behind = head - UV.x;
	if (behind < 0.0) {
		discard;
	}
	float life = 1.0 - clamp(behind / max(tail, 0.001), 0.0, 1.0);
	float fade = 1.0 - smoothstep(sweep, 1.0, progress);
	float across = 1.0 - abs(UV.y * 2.0 - 1.0);
	float n = vfx_noise(vec2(UV.x * 9.0 + seed * 13.1, UV.y * 2.5 + seed));
	float bristle = vfx_noise(vec2(UV.x * 1.5 + seed * 3.0, UV.y * 18.0));
	float edge = (1.0 - life * fade) * 0.85 + n * 0.28 - 0.08;
	float body = smoothstep(edge, edge + 0.08, across);
	if (body <= 0.01) {
		discard;
	}
	float core = smoothstep(edge + 0.15, edge + 0.42, across);
	vec3 rgb = mix(ink_color.rgb, color.rgb, mix(1.0, core, ink));
	rgb = mix(rgb, vec3(1.0, 0.98, 0.9), smoothstep(0.08, 0.0, behind) * 0.65 * core);
	float a_out = body * opacity * color.a * (0.72 + 0.28 * bristle) * clamp(fade * 1.6, 0.0, 1.0);
	if (drawn > 0.5) {
		vec4 o = vfx_ink(rgb, a_out, UV, vec2(UV.x * 14.0, UV.y * 3.0) + seed, ink_color.rgb);
		rgb = o.rgb;
		a_out = o.a;
	}
	ALBEDO = rgb;
	ALPHA = a_out;
}
