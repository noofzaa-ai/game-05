shader_type spatial;
// Flat effect shapes drawn on a quad: glow, impact star, ink splat, ring, light beam, stun swirl,
// afterimage silhouette, crossed slashes, a jagged lightning bolt and a licking flame. The shape is a
// uniform (`mode`), so one compiled shader serves all of them. billboard: 0 = as placed, 1 = faces the
// camera, 2 = turns around the up axis only, 3 = turns around its own long (local y) axis to face the
// camera (a bolt stretched between two points).
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled, blend_mix;

#include "res://client/vfx/vfx_common.gdshaderinc"

uniform int mode = 0;  // 0 glow, 1 star, 2 splat, 3 ring, 4 beam, 5 swirl, 6 ghost, 7 cross, 8 bolt, 9 flame
uniform int billboard = 1;
uniform vec4 color : source_color = vec4(1.0, 0.7, 0.2, 1.0);
uniform vec4 ink_color : source_color = vec4(0.06, 0.05, 0.08, 1.0);
uniform float ink = 0.0;
uniform float progress = 0.0;
uniform float seed = 0.0;
uniform float opacity = 1.0;
uniform float drawn = 0.0;  // 1 = ink-wash look (client/vfx/ink_vfx.gd, graphics setting drawn_style)
uniform float spikes = 10.0;
uniform float spin = 0.0;  // radians, turned by the CPU over time
uniform float pull = 0.0;  // meters drawn toward the camera, so a spark at a hit point is not hidden inside the body it hit

void vertex() {
	if (billboard == 1) {
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
		MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
		MODELVIEW_MATRIX[3].z += pull;
	} else if (billboard == 2) {
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(normalize(cross(vec3(0.0, 1.0, 0.0), INV_VIEW_MATRIX[2].xyz)), 0.0), vec4(0.0, 1.0, 0.0, 0.0), vec4(normalize(cross(INV_VIEW_MATRIX[0].xyz, vec3(0.0, 1.0, 0.0))), 0.0), MODEL_MATRIX[3]);
		MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	} else if (billboard == 3) {
		vec3 axis = MODEL_MATRIX[1].xyz;
		float len = max(length(axis), 0.0001);
		vec3 up = axis / len;
		vec3 to_cam = INV_VIEW_MATRIX[3].xyz - MODEL_MATRIX[3].xyz;
		vec3 side = cross(up, to_cam);
		side = length(side) > 0.0001 ? normalize(side) : normalize(cross(up, vec3(0.0, 0.0, 1.0) + up.yzx * 0.01));
		vec3 facing = cross(side, up);
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(side * length(MODEL_MATRIX[0].xyz), 0.0), vec4(axis, 0.0), vec4(facing, 0.0), MODEL_MATRIX[3]);
	}
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	p.y = -p.y;
	float cs = cos(spin);
	float sn = sin(spin);
	vec2 q = vec2(p.x * cs - p.y * sn, p.x * sn + p.y * cs);
	float r = length(p);
	float a = atan(q.y, q.x);
	float grow = 1.0 - pow(1.0 - clamp(progress, 0.0, 1.0), 3.0);
	float fade = 1.0 - smoothstep(0.35, 1.0, progress);
	vec3 rgb = color.rgb;
	float alpha = 0.0;
	if (mode == 0) {  // soft glow with a hot center
		alpha = pow(clamp(1.0 - r, 0.0, 1.0), 1.6);
		rgb = mix(color.rgb, vec3(1.0), smoothstep(0.55, 1.0, alpha) * 0.8);
		alpha *= 1.0 - progress;
	} else if (mode == 1) {  // impact star: sharp spikes of random length
		float k = max(spikes, 3.0);
		float sector = floor((a / 6.2831853 + 0.5) * k);
		float f = fract((a / 6.2831853 + 0.5) * k);
		float len = (0.45 + 0.55 * vfx_hash(vec2(sector, seed))) * (0.35 + 0.65 * grow);
		float thin = clamp(1.0 - r / len, 0.0, 1.0);
		float spike = smoothstep(thin * 0.5 + 0.001, 0.0, abs(f - 0.5)) * step(r, len);
		float center = smoothstep(0.32 * grow + 0.02, 0.0, r);
		alpha = max(spike, center) * fade;
		rgb = mix(color.rgb, vec3(1.0, 0.98, 0.9), max(center, thin * 0.6));
		rgb = mix(rgb, ink_color.rgb, ink * smoothstep(0.6, 1.0, r / max(len, 0.01)) * spike);
	} else if (mode == 2) {  // ink splat: a ragged blob with droplets flung out
		float blob = (0.42 + 0.16 * vfx_noise(vec2(a * 2.2 + seed * 7.0, seed))) * (0.45 + 0.55 * grow);
		float m = smoothstep(blob + 0.02, blob - 0.02, r);
		for (int i = 0; i < 7; i++) {
			float fi = float(i);
			float da = vfx_hash(vec2(fi, seed + 1.7)) * 6.2831853;
			float dd = (0.55 + 0.4 * vfx_hash(vec2(seed, fi + 3.1))) * (0.3 + 0.7 * grow);
			float dr = 0.035 + 0.07 * vfx_hash(vec2(fi + 9.0, seed));
			vec2 c = vec2(cos(da), sin(da)) * dd;
			m = max(m, smoothstep(dr + 0.015, dr - 0.015, length(p - c)));
		}
		float dry = vfx_noise(p * 5.0 + seed * 4.0);
		m *= step(smoothstep(0.45, 1.0, progress) * 1.05, dry + 0.05);
		alpha = m;
		rgb = mix(color.rgb, ink_color.rgb, ink * smoothstep(0.0, blob, r * 1.3));
	} else if (mode == 3) {  // brush ring racing outward
		float radius = mix(0.18, 0.92, grow);
		float width = mix(0.16, 0.03, progress);
		float n = vfx_noise(vec2(a * 3.0 + seed * 5.0, progress * 2.0));
		float d = abs(r - radius) + (n - 0.5) * 0.06;
		alpha = smoothstep(width, width * 0.3, d) * (1.0 - progress);
		rgb = mix(color.rgb, ink_color.rgb, ink * smoothstep(0.0, width, d));
	} else if (mode == 4) {  // a soft column of light, streaks rising through it
		float x = abs(p.x);
		float column = exp(-x * x * 9.0);
		float rise = vfx_noise(vec2(p.x * 5.0 + seed, UV.y * 3.0 + progress * 6.0));
		float ends = smoothstep(0.0, 0.35, UV.y) * smoothstep(1.0, 0.85, UV.y);
		alpha = column * ends * (0.55 + 0.45 * rise) * smoothstep(0.0, 0.12, progress) * (1.0 - smoothstep(0.55, 1.0, progress));
		rgb = mix(color.rgb, vec3(1.0), column * 0.5);
	} else if (mode == 5) {  // stun: three stars circling and a faint ring
		float ring = smoothstep(0.08, 0.0, abs(r - 0.7)) * 0.35;
		float stars = 0.0;
		for (int i = 0; i < 3; i++) {
			float ang = spin + float(i) * 2.0943951;
			vec2 c = vec2(cos(ang), sin(ang)) * 0.7;
			vec2 d = p - c;
			float dl = length(d);
			float pts = abs(cos(atan(d.y, d.x) * 2.5));
			stars = max(stars, smoothstep(0.2 * (0.45 + 0.55 * pts), 0.0, dl));
		}
		alpha = max(ring, stars);
		rgb = mix(color.rgb, vec3(1.0), stars * 0.4);
	} else if (mode == 6) {  // afterimage: a brushy silhouette of a standing figure
		float head = length(p - vec2(0.0, 0.62)) - 0.2;
		float torso_w = mix(0.34, 0.24, clamp((p.y + 0.9) / 1.3, 0.0, 1.0));
		float torso = max(abs(p.x) - torso_w, abs(p.y + 0.22) - 0.66);
		float d = min(head, torso) + (vfx_noise(p * 6.0 + seed) - 0.5) * 0.08;
		alpha = smoothstep(0.03, -0.03, d) * (1.0 - progress) * (0.45 + 0.35 * vfx_noise(vec2(p.x * 2.0, p.y * 14.0 + seed)));
		rgb = mix(color.rgb, ink_color.rgb, ink * smoothstep(-0.12, 0.0, d));
	} else if (mode == 8) {  // lightning bolt along the quad's height: a jagged white-hot core that flickers
		float t = UV.y;
		float jag = (vfx_noise(vec2(t * 7.0, seed * 3.0 + floor(progress * 14.0))) - 0.5) * 0.9
			+ (vfx_noise(vec2(t * 23.0, seed * 7.0 + floor(progress * 14.0))) - 0.5) * 0.35;
		jag *= smoothstep(0.0, 0.12, t) * smoothstep(1.0, 0.88, t);
		float d = abs(p.x - jag);
		float core = smoothstep(0.09, 0.0, d);
		float halo = smoothstep(0.55, 0.0, d) * 0.45;
		float flicker = 0.65 + 0.35 * step(0.35, vfx_hash(vec2(floor(progress * 18.0), seed)));
		alpha = max(core, halo) * flicker * (1.0 - smoothstep(0.45, 1.0, progress));
		rgb = mix(color.rgb, vec3(1.0), core);
	} else if (mode == 9) {  // flame: tongues of fire rising from the bottom edge, hot yellow core, ember edge
		float t = 1.0 - UV.y;  // 0 at the bottom edge (the standing quad's UV.y runs top to bottom)
		float rise = t * 2.2 - progress * 3.0;
		float sway = (vfx_noise(vec2(rise, seed)) - 0.5) * 0.7 * t;
		float tongues = 0.55 + 0.45 * vfx_noise(vec2(p.x * 3.5 + seed * 2.0, rise * 1.5));
		float width = mix(0.8, 0.12, t) * tongues;
		float d = abs(p.x - sway) / max(width, 0.01);
		float top = 1.0 - smoothstep(0.45, 1.0, t + (vfx_noise(vec2(p.x * 5.0 + seed, rise * 2.0)) - 0.5) * 0.5);
		float lick = smoothstep(1.0, 0.5, d) * top * smoothstep(0.0, 0.06, t);
		alpha = lick * smoothstep(0.0, 0.08, progress) * (1.0 - smoothstep(0.5, 1.0, progress));
		float heat = smoothstep(0.75, 0.0, d) * (1.0 - t * 0.8);
		rgb = mix(color.rgb, vec3(1.0, 0.9, 0.4), heat);
	} else {  // two crossed slashes (critical)
		float len = 0.95 * grow;
		float d1 = abs(q.x - q.y) * 0.7071;
		float d2 = abs(q.x + q.y) * 0.7071;
		float taper = clamp(1.0 - r / max(len, 0.01), 0.0, 1.0);
		float w = 0.11 * taper + 0.004;
		float m = max(smoothstep(w, w * 0.3, d1), smoothstep(w, w * 0.3, d2)) * step(r, len);
		alpha = m * fade;
		rgb = mix(ink_color.rgb, color.rgb, mix(1.0, smoothstep(w * 0.9, w * 0.2, min(d1, d2)), ink));
		rgb = mix(rgb, vec3(1.0), taper * 0.4);
	}
	float a_out = clamp(alpha * opacity * color.a, 0.0, 1.0);
	if (drawn > 0.5) {
		vec4 o = vfx_ink(rgb, a_out, UV, UV * 7.0 + seed, ink_color.rgb);
		rgb = o.rgb;
		a_out = o.a;
	}
	if (a_out <= 0.004) {
		discard;
	}
	ALBEDO = rgb;
	ALPHA = a_out;
}
