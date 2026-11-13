shader_type spatial;
// Drawn battle look, material part (tech-artist 2026-11-13; default since Boss picked ink_c): the stage's own surfaces painted like an ink-and-wash
// illustration. Replaces a map StandardMaterial3D (same albedo colour / texture / vertex colour inputs) with:
// - 2-3 flat light bands instead of a smooth gradient (sun and lamps),
// - pen hatching on the sides turned away from the sun (world-anchored strokes, so they do not swim). Done in
//   fragment(), not light(): Compatibility draws a shadowed sun in an additive pass, where darkening is clamped
//   away, so cast shadows cannot be hatched here (option B/C's screen pass does that),
// - a soft, low-contrast watercolour wash (large, lighter and darker pools around the true colour) and subtle paper grain,
// - colour pulled a little toward a muted, warm palette (greens and browns keep their hue).
// Target: GL Compatibility (WebGL2, mobile). Cost: ~40 ALU ops of value noise per pixel, one texture read.
// Compatibility renderer only features (no screen/depth textures). Procedural noise, no textures yet: the
// final paper/wash would be painted textures (Codex workflow), which is cheaper than this ALU noise.
render_mode diffuse_lambert, specular_disabled, cull_back;

uniform vec4 albedo : source_color = vec4(1.0);
uniform bool use_texture = false;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_vertex_color = false;
uniform bool two_sided = false;

group_uniforms bands;
uniform float band_low = 0.12;   // lit amount where the shadow band ends
uniform float band_high = 0.55;  // lit amount where the full-light band starts
uniform float mid_level = 0.55;  // brightness of the middle band (0 = as dark as shadow, 1 = full light)
uniform float band_soft = 0.03;
group_uniforms;

group_uniforms hatching;
uniform float hatch_strength = 0.55;  // how much a stroke darkens (0 = no hatching)
uniform float hatch_density = 6.0;    // strokes per metre
uniform vec3 sun_direction = vec3(0.47, 0.53, 0.70);  // towards the sun, world space (set from the stage's sun)
group_uniforms;

group_uniforms painted_ground;
// A painted watercolour ground (art/maps/<stage>/...): sampled in world XZ on upward faces and multiplied over the
// art's own colour (vertex colour picks dirt vs grass). Off when no texture is set (use_ground = false).
uniform bool use_ground = false;
uniform sampler2D ground_a : source_color, filter_linear_mipmap, repeat_enable;  // e.g. dirt / floor tile
uniform sampler2D ground_b : source_color, filter_linear_mipmap, repeat_enable;  // e.g. grass / sand
uniform float ground_a_metres = 4.0;  // one texture repeat, in metres
uniform float ground_b_metres = 4.0;
uniform bool ground_b_by_green = true;  // true: green art (grass) takes ground_b, the rest ground_a; false: all ground_a
uniform float ground_average = 0.6;  // the textures' mean brightness as sampled (Compatibility returns raw sRGB): strokes are centred on it
uniform float ground_tint = 0.75;
uniform float ground_strokes = 0.8;  // how strongly the painting's light/dark strokes show (when ground_tint < 1)
uniform float ground_saturation = 1.0;  // saturation of the painting before it is used (muted, earthy: < 1)
uniform vec2 ground_offset = vec2(0.0);  // metres: lines the painting's slab seams up with the modelled ones
uniform float ground_max_y = 1000.0;  // only faces lower than this (world y) are the ground (not wall tops)  // 1 = the painting's hue at the art's brightness, 0 = the art colour unchanged
group_uniforms;

group_uniforms paper;
// A painted paper tile replaces the procedural grain when set (multiplied, centred on its own average).
uniform bool use_paper = false;
uniform sampler2D paper_tex : filter_linear_mipmap, repeat_enable;
uniform float paper_metres = 1.5;
uniform float paper_average = 0.961;  // the tile's mean brightness as sampled, so it neither lightens nor darkens overall
uniform float paper_strength = 3.0;  // the tile is very flat (std ~1.5%): this scales its tooth up
group_uniforms;

group_uniforms paint;
uniform float saturation = 0.9;    // 1 = the art's own colour
uniform vec3 warmth = vec3(1.03, 1.0, 0.93);
uniform float wash_strength = 0.10;  // +-10% brightness at most: pools, not stains
uniform float grain_strength = 0.05;  // +-5%: felt more than seen
group_uniforms;

varying vec3 world_pos;
varying vec3 world_normal;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

// The 2D coordinates a stroke/wash pattern uses on this surface: the plane the surface mostly faces.
vec2 surface_plane(vec3 p, vec3 n) {
	vec3 a = abs(n);
	if (a.y >= a.x && a.y >= a.z) return p.xz;
	if (a.x >= a.z) return p.zy;
	return p.xy;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 colour = albedo.rgb;
	if (use_texture) colour *= texture(albedo_tex, UV).rgb;
	if (use_vertex_color) colour *= COLOR.rgb;
	vec2 plane = surface_plane(world_pos, world_normal);
	if (use_ground && world_normal.y > 0.7 && world_pos.y < ground_max_y) {
		// How much this pixel is "grass" (ground_b): green stronger than red in the art colour.
		float b_amount = ground_b_by_green ? smoothstep(-0.02, 0.06, colour.g - colour.r) : 0.0;
		vec3 a = texture(ground_a, (world_pos.xz + ground_offset) / ground_a_metres).rgb;
		vec3 b = texture(ground_b, (world_pos.xz + ground_offset) / ground_b_metres).rgb;
		vec3 painted = mix(a, b, b_amount);
		painted = mix(vec3(dot(painted, vec3(0.299, 0.587, 0.114))), painted, ground_saturation);
		float art_luma = max(dot(colour, vec3(0.299, 0.587, 0.114)), 0.001);
		float paint_luma = max(dot(painted, vec3(0.299, 0.587, 0.114)), 0.001);
		// keep the art's brightness (lighting of the scene, dark patches) and take the painting's hue and strokes
		// ground_tint 1: the painting's hue at the art's brightness; 0: the art colour, with only the painting's
		// light/dark strokes (pools, pebbles, seams) laid over it.
		vec3 strokes = colour * (paint_luma / ground_average);
		colour = mix(mix(colour, strokes, ground_strokes), painted * (art_luma / paint_luma), ground_tint);
	}
	// Watercolour wash: big soft pools (about 4-6 m) a little lighter or darker than the true colour, centred on
	// it, so the average brightness and hue stay the art's. (The prototype used smaller, darker-only blotches,
	// which read as dirty paint.)
	float wash = value_noise(plane * 0.18) * 0.7 + value_noise(plane * 0.55 + 7.0) * 0.3;
	colour *= 1.0 + wash_strength * smoothstep(0.15, 0.85, wash) * 2.0 - wash_strength;
	// Paper grain: the painted paper tile when set, else fine procedural speckle; both centred (no overall darkening).
	if (use_paper) {
		float tooth = texture(paper_tex, plane / paper_metres).r;
		colour *= 1.0 + (tooth - paper_average) * paper_strength;
	} else {
		float grain = value_noise(plane * 38.0) * 0.7 + hash(floor(plane * 90.0)) * 0.3;
		colour *= 1.0 + grain_strength * (grain - 0.5) * 2.0;
	}
	float luma = dot(colour, vec3(0.299, 0.587, 0.114));
	colour = mix(vec3(luma), colour, saturation) * warmth;
	// Hatching on the sides that face away from the sun: diagonal strokes, a crossing set in patches.
	float away = 1.0 - smoothstep(-0.05, 0.25, dot(world_normal, normalize(sun_direction)));
	float wobble = value_noise(plane * 1.7) * 0.6;
	float s1 = abs(fract((plane.x + plane.y) * hatch_density + wobble) - 0.5);
	float s2 = abs(fract((plane.x - plane.y) * hatch_density * 0.9 + wobble) - 0.5);
	float stroke1 = 1.0 - smoothstep(0.08, 0.16, s1);
	float stroke2 = (1.0 - smoothstep(0.06, 0.13, s2)) * step(0.5, value_noise(plane * 0.6 + 3.0));
	float stroke = max(stroke1, stroke2) * away * smoothstep(0.25, 0.55, value_noise(plane * vec2(9.0, 2.0)));
	colour *= 1.0 - stroke * hatch_strength;
	ALBEDO = clamp(colour, 0.0, 1.0);
	if (two_sided && !FRONT_FACING) NORMAL = -NORMAL;
}

void light() {
	float lit = clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * ATTENUATION;
	float band = mix(0.0, mid_level, smoothstep(band_low - band_soft, band_low + band_soft, lit));
	band = mix(band, 1.0, smoothstep(band_high - band_soft, band_high + band_soft, lit));
	DIFFUSE_LIGHT += LIGHT_COLOR * band / PI;
}
