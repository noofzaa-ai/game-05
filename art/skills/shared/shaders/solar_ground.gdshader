shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;

// A decorative charred footprint, carried by the authored GLB. No terrain or
// collision changes; gameplay remains the forward query from the manifest.
uniform float cast_time = 0.0;
uniform float impact_time = 1.12;
uniform float opacity = 1.0;
uniform float ground_kind = 0.0; // charred footprint 0, authored fracture plates 1
varying vec3 ground_position;

void vertex() {
	ground_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p), u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0)), u.x), u.y);
}
void fragment() {
	float r = length(UV - vec2(0.5)) * 2.0;
	float n = noise(ground_position.xz * 1.65);
	float broad = noise(ground_position.xz * 0.58 + vec2(4.3, 2.9));
	float edge = 1.0 - smoothstep(0.86, 1.02, r + (noise(UV * 7.0) - 0.5) * 0.12);
	if (ground_kind > 0.5) edge = 1.0;
	float hot = 1.0 - smoothstep(0.30, 1.80, cast_time - impact_time);
	// Unequal dark red plate areas make the crack network read as broken
	// ground. Avoid a uniform flat disc underneath an equally bright web.
	vec3 coal = mix(vec3(0.037, 0.004, 0.003), vec3(0.14, 0.016, 0.007), broad);
	vec3 scorched = mix(coal, vec3(0.23, 0.019, 0.006), hot * (0.18 + n * 0.38));
	float light = 0.78 + 0.22 * clamp(dot(normalize(NORMAL), normalize(vec3(-0.35, 0.80, 0.45))), 0.0, 1.0);
	ALBEDO = scorched * light;
	ALPHA = edge * opacity * (ground_kind > 0.5 ? 1.0 : 0.96);
}
