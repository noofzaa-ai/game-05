shader_type spatial;
// Character Artist, zorx. The Studio's ink hull (line-art.js addInkHull): the face/hair drawn again,
// grown along the skinned normal and showing only its back faces, so it reads as a line where the
// surfaces overlap. Target: Compatibility renderer. Bind-pose positions come from UV/UV2 (see the model).
render_mode unshaded, cull_front, fog_disabled;

uniform float grow = 0.0019; // GLB units: hair 0.0019, head 0.0014
uniform bool is_hair = true;
uniform bool has_rest = false;
uniform vec3 base_color_linear = vec3(0.43, 0.39, 0.52); // hair material colour
uniform bool use_albedo_tex = false; // Hair G: its texture is part of the hull colour (diffuseColor)
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_vertex_color = false; // Hair C-F: COLOR_0 is part of the hull colour

varying vec3 rest_pos;
varying vec4 vertex_color;

void vertex() {
	rest_pos = has_rest ? vec3(UV.x, UV.y, UV2.x) : VERTEX;
	vertex_color = COLOR;
	VERTEX += normalize(NORMAL) * grow;
}

vec3 linear_to_srgb(vec3 v) {
	vec3 low = 12.92 * v;
	vec3 high = 1.055 * pow(max(v, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055;
	return mix(low, high, step(vec3(0.0031308), v));
}

void fragment() {
	if (!is_hair) {
		// Recessed eye geometry can expose the expanded hull through the liner.
		vec2 socket = (vec2(abs(rest_pos.x), rest_pos.y) - vec2(0.043, 0.359)) / vec2(0.036, 0.030);
		if (rest_pos.z > 0.023 && dot(socket, socket) < 1.0) {
			discard;
		}
	}
	vec3 diffuse = base_color_linear;
	if (use_albedo_tex) {
		diffuse *= texture(albedo_tex, UV).rgb;
	}
	if (use_vertex_color) {
		diffuse *= vertex_color.rgb;
	}
	vec3 c = is_hair ? mix(diffuse * 0.28, vec3(0.027, 0.017, 0.039), 0.60) : vec3(0.24, 0.105, 0.095);
	ALBEDO = OUTPUT_IS_SRGB ? linear_to_srgb(c) : c;
}
