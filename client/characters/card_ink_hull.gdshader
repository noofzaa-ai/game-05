shader_type spatial;
// Technical Artist, zorx. Card-only ink line (hub ink-wash look, 2026-11-14): the mesh drawn again, pushed out
// along its normals and showing only its back faces, in a dark-brown ink. Unlike the Studio hull
// (studio05_ink.gdshader, a fixed grow in GLB units) the width is a fraction of the card render's height, so
// the line reads the same on a phone card and a desktop card. A slow wobble along the body gives it a brush
// feel. Used only by card portraits (studio05_character_model.gd card_ink); battle and Studio never use it.
// Target: Compatibility renderer (the web build ignores a written POSITION, so the push is in 3D).
render_mode unshaded, cull_front, fog_disabled, shadows_disabled;

uniform float line_fraction = 0.0042; // line width as a fraction of the viewport height
uniform float wobble = 0.22; // 0 = even line, 0.22 = width varies +-22% along the body (brush pressure)
uniform float min_pixels = 1.8; // never thinner than this (thin blades and bow strings keep a solid line)
uniform vec3 ink_linear = vec3(0.010, 0.0045, 0.0025); // near-black brown (#1c120c), not black
uniform bool is_hair = false; // hair: the ink takes a little of the hair colour
uniform bool eye_cut = false; // head: no line inside the eye sockets (recessed eye geometry)
uniform bool has_rest = false; // head/hair A-F: bind-pose positions baked into UV/UV2 (see the model)
uniform vec3 base_color_linear = vec3(0.43, 0.39, 0.52); // hair colour (set by _apply_colors)
uniform bool use_vertex_color = false;

varying vec3 rest_pos;
varying vec4 vertex_color;

void vertex() {
	rest_pos = has_rest ? vec3(UV.x, UV.y, UV2.x) : VERTEX;
	vertex_color = COLOR;
	vec3 direction = normalize(NORMAL);
	float units_to_view = max(length(mat3(MODELVIEW_MATRIX) * direction), 0.000001);
	float depth = max(-(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z, 0.0001);
	// One viewport-height fraction in view units at this depth (perspective; orthographic has no depth term).
	float view_units = 2.0 * line_fraction / abs(PROJECTION_MATRIX[1][1]);
	if (PROJECTION_MATRIX[3][3] < 0.5) {
		view_units *= depth;
	}
	vec3 q = VERTEX * 9.0;
	float brush = sin(q.x * 1.7 + q.y * 2.3) * sin(q.y * 1.3 - q.z * 2.9 + 1.1);
	view_units *= 1.0 + wobble * brush;
	float pixel_units = 2.0 / (abs(PROJECTION_MATRIX[1][1]) * max(VIEWPORT_SIZE.y, 1.0));
	if (PROJECTION_MATRIX[3][3] < 0.5) {
		pixel_units *= depth;
	}
	view_units = max(view_units, min_pixels * pixel_units);
	VERTEX += direction * view_units / units_to_view;
}

vec3 linear_to_srgb(vec3 v) {
	vec3 low = 12.92 * v;
	vec3 high = 1.055 * pow(max(v, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055;
	return mix(low, high, step(vec3(0.0031308), v));
}

void fragment() {
	if (eye_cut) {
		// Same socket cut as studio05_ink.gdshader (the hull would show through the liner).
		vec2 socket = (vec2(abs(rest_pos.x), rest_pos.y) - vec2(0.043, 0.359)) / vec2(0.036, 0.030);
		if (rest_pos.z > 0.023 && dot(socket, socket) < 1.0) {
			discard;
		}
	}
	vec3 c = ink_linear;
	if (is_hair) {
		vec3 hair = base_color_linear * (use_vertex_color ? vertex_color.rgb : vec3(1.0));
		c = mix(ink_linear, hair * 0.15, 0.12);
	}
	ALBEDO = OUTPUT_IS_SRGB ? linear_to_srgb(c) : c;
}
