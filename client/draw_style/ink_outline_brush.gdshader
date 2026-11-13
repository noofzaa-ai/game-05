shader_type spatial;
// Draw-style prototype (tech-artist 2026-11-13): the ink outline (client/ink_outline.gdshader) as a brush
// stroke: thicker, and its width swells and thins along the model (world-position noise), so the line looks
// hand-inked instead of an even technical pen. Same inverted-hull method, same cost per draw.
render_mode cull_front, unshaded, shadows_disabled;

uniform vec4 ink_color : source_color = vec4(0.10, 0.08, 0.07, 1.0);
uniform float width = 0.005;
uniform float min_pixels = 0.0;
uniform float max_pixels = 3.6;
uniform float wobble = 0.55;      // 0 = even line, 1 = width goes 0..2x
uniform float wobble_scale = 2.2; // swellings per metre

float hash(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

float value_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	float a = mix(mix(hash(i), hash(i + vec3(1, 0, 0)), u.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), u.x), u.y);
	float b = mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), u.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), u.x), u.y);
	return mix(a, b, u.z);
}

void vertex() {
	vec3 direction = normalize(NORMAL);
	float units_to_view = max(length(mat3(MODELVIEW_MATRIX) * direction), 0.000001);
	float depth = max(-(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z, 0.0001);
	float pixel_size = 2.0 / (abs(PROJECTION_MATRIX[1][1]) * max(VIEWPORT_SIZE.y, 1.0));
	if (PROJECTION_MATRIX[3][3] < 0.5) {
		pixel_size *= depth;
	}
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float swell = 1.0 + wobble * (value_noise(world * wobble_scale) * 2.0 - 1.0);
	float pixels = clamp(width * units_to_view / pixel_size, min_pixels, max_pixels) * swell;
	VERTEX += direction * pixels * pixel_size / units_to_view;
}

void fragment() {
	ALBEDO = ink_color.rgb;
}
