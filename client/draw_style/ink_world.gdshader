shader_type spatial;
// Draw-style prototype A/C (tech-artist 2026-11-13): the stage's own surfaces painted like an ink-and-wash
// illustration. Replaces a map StandardMaterial3D (same albedo colour / texture / vertex colour inputs) with:
// - 2-3 flat light bands instead of a smooth gradient (sun and lamps),
// - pen hatching on the sides turned away from the sun (world-anchored strokes, so they do not swim). Done in
//   fragment(), not light(): Compatibility draws a shadowed sun in an additive pass, where darkening is clamped
//   away, so cast shadows cannot be hatched here (option B/C's screen pass does that),
// - a watercolour wash (soft blotches) and paper grain over the colour,
// - colour pulled toward a muted, warm, earthy palette.
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

group_uniforms paint;
uniform float saturation = 0.72;
uniform vec3 warmth = vec3(1.05, 1.0, 0.86);
uniform float wash_strength = 0.28;
uniform float grain_strength = 0.16;
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
	// watercolour wash: two octaves of soft blotches, darker where the pigment pooled
	float wash = value_noise(plane * 0.35) * 0.65 + value_noise(plane * 1.3 + 7.0) * 0.35;
	colour *= 1.0 - wash_strength * (wash - 0.35);
	// paper grain: fine speckle, fixed to the surface
	float grain = value_noise(plane * 38.0) * 0.6 + hash(floor(plane * 90.0)) * 0.4;
	colour *= 1.0 - grain_strength * grain;
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
