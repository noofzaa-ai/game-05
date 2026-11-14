// Small noise helpers shared by the effect shaders (brush edges, ink blots, cracks).

float vfx_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vfx_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(vfx_hash(i), vfx_hash(i + vec2(1.0, 0.0)), u.x),
		mix(vfx_hash(i + vec2(0.0, 1.0)), vfx_hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

// Smallest angle between two angles (radians), always positive.
float vfx_angle_gap(float a, float b) {
	float d = mod(a - b + 3.14159265, 6.2831853) - 3.14159265;
	return abs(d);
}
// --- Ink-wash treatment (Boss 2026-11-15: effects drawn in ink like the stages and cards) -----------------------
// Turns a glowing effect pixel (colour + alpha) into paint on paper, in one pass and with no texture read:
// - the soft alpha fringe becomes an ink line (a band just inside the silhouette): a dark shade of the effect's own
//   hue mixed with the pen ink, so fire stays fire-coloured at the edge; its threshold is broken up by grain noise
//   so the edge looks dry-brushed instead of soft or additive. Only where alpha changes (an edge), not on a fade,
//   and thinner on sprites that are only a few pixels on screen (else motes become black specks);
// - the inside becomes flat wash glazes (alpha stepped to 1/4, 1/2, 3/4, 1), so there is no smooth glow falloff,
//   and paint covers a little more than the light did (alpha x1.35), so effects still read on a light ground;
// - brightness steps to 3 tones with the hue kept (fire stays orange, frost blue), darks stay dark;
// - colour is pulled a little toward grey and warm paper (the watercolour palette).
// uv: the sprite's 0..1 UV (for its size on screen); grain_p: a coordinate that moves with the effect.
// Fragment only (uses fwidth). Returns (rgb, alpha); alpha 0 means "nothing here". ~45 ALU, no texture.
float vfx_ink_step(float edge, float x, float fw) {
	return smoothstep(edge - fw, edge + fw, x);
}

vec4 vfx_ink(vec3 rgb, float alpha, vec2 uv, vec2 grain_p, vec3 ink_rgb) {
	float fw = max(fwidth(alpha), 0.002);
	float n = vfx_noise(grain_p) * 0.65 + vfx_noise(grain_p * 3.1 + 7.3) * 0.35;
	float a = min(alpha * 1.35, 1.0) + (n - 0.5) * 0.16;  // paper tooth bites into the edge unevenly
	float lo = 0.07;
	float cover = vfx_ink_step(lo, a, fw);
	if (cover <= 0.0) {
		return vec4(0.0);
	}
	float glaze = (vfx_ink_step(0.2, a, fw) + vfx_ink_step(0.42, a, fw) + vfx_ink_step(0.64, a, fw) + vfx_ink_step(0.84, a, fw)) * 0.235;
	float band = max(fw * 2.2, 0.05);
	vec2 duv = fwidth(uv);
	float small = smoothstep(0.03, 0.1, max(duv.x, duv.y));  // 1 = the sprite is ~10-30 px across
	float rim = (1.0 - vfx_ink_step(lo + band, a, fw)) * smoothstep(0.003, 0.015, fwidth(alpha)) * (1.0 - small * 0.8);
	float v = max(max(rgb.r, rgb.g), rgb.b);
	vec3 hue = rgb / max(v, 0.0001);
	float tone = mix(v, 0.62, vfx_ink_step(0.28, v, 0.03));
	tone = mix(tone, 0.9, vfx_ink_step(0.72, v, 0.03));
	vec3 col = hue * tone;
	float l = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(l), col, 0.82) * vec3(1.0, 0.97, 0.9);
	vec3 pen = mix(hue * 0.28, ink_rgb, 0.55);  // dark shade of the effect's own colour
	col = mix(col, pen, rim * 0.9);
	return vec4(col, cover * max(glaze, rim * 0.85));
}
