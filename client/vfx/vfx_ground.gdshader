shader_type spatial;
// Marks on the ground (a flat quad): a shockwave ring, cracks from a heavy blow, an ink stain where a
// fighter fell, a glowing circle at a rest point. The mark is a uniform (`mode`), so this compiles once.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled, blend_mix;

#include "res://client/vfx/vfx_common.gdshaderinc"

uniform int mode = 0;  // 0 ring, 1 crack, 2 stain, 3 glyph
uniform vec4 color : source_color = vec4(0.9, 0.8, 0.6, 1.0);
uniform vec4 ink_color : source_color = vec4(0.06, 0.05, 0.08, 1.0);
uniform float ink = 0.5;
uniform float progress = 0.0;
uniform float seed = 0.0;
uniform float opacity = 1.0;
uniform float spin = 0.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float grow = 1.0 - pow(1.0 - clamp(progress, 0.0, 1.0), 3.0);
	vec3 rgb = color.rgb;
	float alpha = 0.0;
	if (mode == 0) {  // shockwave: a thick dusty brush ring that thins as it spreads
		float radius = mix(0.1, 0.94, grow);
		float width = mix(0.2, 0.025, progress);
		float n = vfx_noise(vec2(a * 4.0 + seed * 3.0, r * 6.0));
		float d = abs(r - radius) + (n - 0.5) * 0.08;
		alpha = smoothstep(width, width * 0.2, d) * (1.0 - progress);
		alpha = max(alpha, smoothstep(radius, 0.0, r) * 0.18 * (1.0 - progress));
		rgb = mix(color.rgb, ink_color.rgb, ink * smoothstep(0.0, width, d));
	} else if (mode == 1) {  // cracks radiating from the blow, glowing at first, then dark, then gone
		float m = 0.0;
		float count = 7.0 + floor(vfx_hash(vec2(seed, 2.0)) * 4.0);
		for (int i = 0; i < 10; i++) {
			float fi = float(i);
			if (fi < count) {
				float base = (fi + vfx_hash(vec2(fi, seed)) * 0.6) / count * 6.2831853;
				float wiggle = (vfx_noise(vec2(r * 7.0, fi * 3.3 + seed)) - 0.5) * 0.7;
				float len = (0.55 + 0.45 * vfx_hash(vec2(seed, fi + 5.0))) * min(1.0, grow * 1.6);
				float d = vfx_angle_gap(a, base + wiggle) * r;
				float w = 0.04 * clamp(1.0 - r / max(len, 0.01), 0.0, 1.0) + 0.004;
				m = max(m, smoothstep(w, w * 0.3, d) * step(r, len));
			}
		}
		float crater = smoothstep(0.2 + 0.05 * vfx_noise(p * 6.0 + seed), 0.1, r) * 0.75;
		m = max(m, crater);
		float hot = 1.0 - smoothstep(0.0, 0.35, progress);
		rgb = mix(ink_color.rgb, color.rgb, hot * (1.0 - ink * 0.5));
		alpha = m * (1.0 - smoothstep(0.55, 1.0, progress));
	} else if (mode == 2) {  // ink stain that soaks in and dries away
		float edge = (0.62 + 0.25 * vfx_noise(vec2(a * 2.0 + seed * 5.0, seed))) * (0.5 + 0.5 * grow);
		float m = smoothstep(edge, edge - 0.08, r);
		float dry = vfx_noise(p * 4.0 + seed * 2.0);
		m *= step(smoothstep(0.4, 1.0, progress) * 1.1, dry + 0.08);
		alpha = m * 0.85;
		rgb = mix(color.rgb, ink_color.rgb, ink);
	} else {  // rest glyph: two circles and turning tick marks
		float rings = max(smoothstep(0.035, 0.0, abs(r - 0.86)), smoothstep(0.025, 0.0, abs(r - 0.7)));
		float ticks = step(0.72, r) * step(r, 0.84) * smoothstep(0.12, 0.0, abs(fract((a + spin) / 6.2831853 * 12.0) - 0.5) * 2.0 - 0.75);
		float inner = smoothstep(0.7, 0.0, r) * 0.3;
		float show = smoothstep(0.0, 0.15, progress) * (1.0 - smoothstep(0.6, 1.0, progress));
		alpha = max(max(rings, ticks), inner) * show * grow;
		rgb = mix(color.rgb, vec3(1.0), rings * 0.4);
	}
	if (alpha <= 0.004) {
		discard;
	}
	ALBEDO = rgb;
	ALPHA = clamp(alpha * opacity * color.a, 0.0, 1.0);
}
