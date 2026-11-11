shader_type spatial;
// The Studio's ink hull (line-art.js addInkHull): the face/hair drawn again, grown along the
// skinned normal and showing only its back faces, so it reads as a line where the surfaces overlap.
render_mode unshaded, cull_front, fog_disabled;

uniform float grow = 0.0019; // GLB units: hair 0.0019, head 0.0014
uniform bool is_hair = true;
uniform bool has_rest = false;
uniform vec3 base_color_linear = vec3(0.43, 0.39, 0.52);

varying vec3 rest_pos;

void vertex() {
	rest_pos = has_rest ? vec3(UV.x, UV.y, UV2.x) : VERTEX;
	VERTEX += normalize(NORMAL) * grow;
}

vec3 linear_to_srgb(vec3 v) {
	vec3 low = 12.92 * v;
	vec3 high = 1.055 * pow(max(v, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055;
	return mix(low, high, step(vec3(0.0031308), v));
}

void fragment() {
	if (!is_hair) {
		vec2 socket = (vec2(abs(rest_pos.x), rest_pos.y) - vec2(0.043, 0.359)) / vec2(0.036, 0.030);
		if (rest_pos.z > 0.023 && dot(socket, socket) < 1.0) {
			discard;
		}
	}
	vec3 c = is_hair ? mix(base_color_linear * 0.28, vec3(0.027, 0.017, 0.039), 0.60) : vec3(0.24, 0.105, 0.095);
	ALBEDO = OUTPUT_IS_SRGB ? linear_to_srgb(c) : c;
}
