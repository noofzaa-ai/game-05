shader_type spatial;
// Port of test05/studio (index.html + eyes/anime-face.js + eyes/eye-makeup.js + line-art.js).
// Cel bands use the Studio's fixed camera-space key; colours are linear. Bind-pose positions
// (GLB units) are baked into UV (x, y) and UV2 (z) at load, because VERTEX here is post-skinning.
render_mode unshaded, cull_disabled, fog_disabled;

uniform vec3 base_color_linear = vec3(0.72, 0.56, 0.48);
uniform int part = 0; // 0 body/outfit, 1 face (Head_Anime), 2 hair
uniform bool has_rest = false;
uniform vec3 iris_tint = vec3(0.5776, 0.2384, 0.0331); // #C98634 in linear
uniform int makeup_style = 0;
uniform bool eyes_visible = true;
uniform float hair_part = -0.003;
uniform float painted_bangs = 0.0;
uniform vec4 flash = vec4(0.0); // game tint (hit flash etc.): rgb, a = strength

varying vec3 rest_pos;
varying vec3 view_n;

void vertex() {
	rest_pos = has_rest ? vec3(UV.x, UV.y, UV2.x) : VERTEX;
}

float studioStroke(float d, float half_width) {
	float aa = clamp(0.5 * fwidth(d), 0.0002, 0.0025);
	return 1.0 - smoothstep(half_width - aa, half_width + aa, abs(d));
}

float lashTip(vec2 eye, vec2 root, vec2 tip, float root_width) {
	vec2 axis = tip - root;
	float along = dot(eye - root, axis) / dot(axis, axis);
	float across = length(eye - root - along * axis);
	float width = root_width * (1.0 - clamp(along, 0.0, 1.0));
	return (1.0 - smoothstep(width - 0.025, width + 0.025, across))
		* smoothstep(-0.15, 0.0, along) * (1.0 - smoothstep(0.92, 1.0, along));
}

vec4 eyeMakeupShadow(vec2 lid, float lid_height) {
	if (makeup_style == 1) {
		float outer = smoothstep(0.0, 0.98, lid.x);
		float span = 1.0 - smoothstep(0.86, 1.22, abs(lid.x));
		float above = smoothstep(-0.10, 0.13, lid_height);
		float falloff = 1.0 - smoothstep(0.08, mix(0.42, 0.97, outer), lid_height);
		vec3 tint = mix(vec3(0.67, 0.41, 0.40), vec3(0.18, 0.070, 0.105), outer);
		return vec4(tint, span * above * falloff * mix(0.22, 0.59, outer));
	}
	float lid_falloff = 1.0 - smoothstep(0.12, 0.65, lid_height);
	float lid_span = 1.0 - smoothstep(0.75, 1.15, abs(lid.x));
	float outer_lid = smoothstep(-0.55, 0.95, lid.x);
	float eyeshadow = smoothstep(-0.15, 0.07, lid_height) * lid_falloff * lid_span;
	vec3 tint = mix(vec3(0.61, 0.27, 0.27), vec3(0.38, 0.12, 0.15), outer_lid);
	return vec4(tint, eyeshadow * mix(0.24, 0.46, outer_lid));
}

vec4 eyeMakeupLiner(vec2 lid, float upper, float lower) {
	if (makeup_style == 1) {
		float outer = smoothstep(-0.64, 0.94, lid.x);
		float span = 1.0 - smoothstep(0.985, 1.025, abs(lid.x));
		float upper_distance = lid.y - upper;
		float upper_ink = smoothstep(-0.13, -0.075, upper_distance)
			* (1.0 - smoothstep(0.035, 0.075, upper_distance - 0.24 * outer));
		float lower_width = mix(0.023, 0.085, outer);
		float lower_ink = (1.0 - smoothstep(lower_width, lower_width + 0.045, abs(lid.y - lower))) * mix(0.34, 0.72, outer);
		float wing_t = clamp((lid.x - 0.81) / 0.42, 0.0, 1.0);
		float wing_top = mix(0.70, 0.71, wing_t);
		float wing_bottom = mix(-0.05, 0.71, wing_t * wing_t);
		float wing = smoothstep(0.81, 0.93, lid.x) * (1.0 - smoothstep(1.20, 1.23, lid.x))
			* smoothstep(-0.025, 0.025, lid.y - wing_bottom) * (1.0 - smoothstep(-0.025, 0.025, lid.y - wing_top));
		wing = max(wing, lashTip(lid, vec2(0.80, 0.53), vec2(1.16, 0.89), 0.15));
		return vec4(vec3(0.043, 0.017, 0.026), max(span * max(upper_ink, lower_ink), wing));
	}
	float lash_width = mix(0.14, 0.30, smoothstep(0.05, 0.86, lid.x));
	float lash = (1.0 - smoothstep(lash_width - 0.04, lash_width + 0.04, abs(lid.y - upper)))
		* (1.0 - smoothstep(0.94, 1.05, abs(lid.x)));
	float wing = lashTip(lid, vec2(0.70, 0.62), vec2(1.20, 0.90), 0.16);
	wing = max(wing, lashTip(lid, vec2(0.82, 0.47), vec2(1.26, 0.61), 0.13));
	wing = max(wing, lashTip(lid, vec2(0.91, 0.32), vec2(1.22, 0.35), 0.10));
	float lower_width = mix(0.035, 0.17, smoothstep(0.64, 0.96, lid.x));
	float lower_lash = (1.0 - smoothstep(lower_width * 0.5, lower_width + 0.04, abs(lid.y - lower)))
		* (1.0 - smoothstep(0.95, 1.025, abs(lid.x)));
	float lower_opacity = mix(0.32, 0.92, smoothstep(0.42, 0.93, lid.x));
	return vec4(vec3(0.042, 0.017, 0.026), max(max(lash, wing), lower_opacity * lower_lash));
}

vec2 eyeSocketRim(float t) {
	vec2 s[7] = vec2[7](vec2(0.3580, 0.3580), vec2(0.3662, 0.3508), vec2(0.3705, 0.3452),
		vec2(0.3718, 0.3443), vec2(0.3710, 0.3452), vec2(0.3680, 0.3500), vec2(0.3620, 0.3620));
	float index = clamp(t, 0.0, 1.0) * 6.0;
	int seg = min(int(index), 5);
	float f = index - float(seg);
	vec2 a = s[max(seg - 1, 0)];
	vec2 b = s[seg];
	vec2 c = s[seg + 1];
	vec2 d = s[min(seg + 2, 6)];
	return b + 0.5 * f * ((c - a) + f * ((2.0 * a - 5.0 * b + 4.0 * c - d) + f * (3.0 * (b - c) + d - a)));
}

vec3 linear_to_srgb(vec3 v) {
	vec3 low = 12.92 * v;
	vec3 high = 1.055 * pow(max(v, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055;
	return mix(low, high, step(vec3(0.0031308), v));
}

void fragment() {
	vec3 n = normalize(NORMAL);
	if (!FRONT_FACING) {
		n = -n;
	}
	vec3 key = normalize(vec3(-0.45, 0.65, 0.72));
	float cel_facing = dot(n, key);
	float band = mix(0.63, 0.88, smoothstep(0.05, 0.09, cel_facing));
	band = mix(band, 1.08, smoothstep(0.56, 0.60, cel_facing));
	vec3 light = base_color_linear * band;
	vec3 p = rest_pos;

	if (part == 2) {
		float crease = max(length(dFdx(n)), length(dFdy(n)));
		float crease_ink = smoothstep(0.14, 0.32, crease);
		float band_slope = fwidth(cel_facing);
		float band_distance = abs(cel_facing - 0.07) / max(band_slope, 0.0001);
		float band_ink = (1.0 - smoothstep(0.24, 0.80, band_distance)) * smoothstep(0.027, 0.10, band_slope);
		float bang_side = abs(p.x - hair_part);
		float bang_t = clamp((0.491 - p.y) / 0.067, 0.0, 1.0);
		float bang_x = 0.010 + 0.045 * bang_t * (1.45 - 0.45 * bang_t);
		float bang_taper = smoothstep(0.0, 0.17, bang_t) * (1.0 - smoothstep(0.67, 1.0, bang_t));
		float bang_front = smoothstep(0.031, 0.057, p.z);
		float bang_ink = studioStroke(bang_side - bang_x, 0.0014 * bang_taper) * bang_taper * bang_front * painted_bangs;
		vec3 ink_color = mix(base_color_linear * 0.19, vec3(0.009, 0.006, 0.018), 0.5);
		light = mix(light, ink_color, max(crease_ink * 0.50, max(band_ink * 0.52, bang_ink * 0.64)));
	}

	if (part == 1 && eyes_visible) {
		float side = abs(p.x);
		float eye_offset = side - 0.039;
		vec2 eye = vec2(eye_offset / 0.024, (p.y - 0.357 - eye_offset * 0.055) / 0.013);
		if (p.z > 0.015 && side < 0.074 && p.y > 0.334 && p.y < 0.415) {
			float socket_t = (side - 0.021) / 0.0445;
			float socket_base = mix(0.358, 0.362, clamp(socket_t, 0.0, 1.0));
			vec2 lid = vec2(2.0 * socket_t - 1.0, (p.y - socket_base) / 0.013);
			vec2 rim = (eyeSocketRim(socket_t) - socket_base) / 0.013;
			float upper = rim.x;
			float lower = rim.y;
			float lid_height = lid.y - upper;
			vec4 shadow = eyeMakeupShadow(lid, lid_height);
			light = mix(light, shadow.rgb, shadow.a);
			float opening = smoothstep(-0.04, 0.04, min(1.0 - abs(lid.x), min(upper - lid.y, lid.y - lower)));
			vec3 eye_color = vec3(0.96, 0.87, 0.76);
			vec2 iris = vec2((eye.x + 0.07) / 0.49, (eye.y + 0.125) / 0.96);
			float radius = length(iris);
			float iris_mask = 1.0 - smoothstep(0.94, 1.01, radius);
			vec3 amber = mix(min(iris_tint * 1.35, vec3(1.0)), iris_tint * 0.24, smoothstep(-0.72, 0.6, iris.y));
			float glint = sin(atan(iris.y, iris.x + 0.0001) * 19.0) * 0.5 + 0.5;
			amber += mix(iris_tint, vec3(1.0), 0.3) * 0.37 * glint * smoothstep(0.35, 0.9, radius) * (1.0 - smoothstep(-0.50, 0.35, iris.y));
			amber = mix(amber, iris_tint * 0.20, smoothstep(0.82, 0.98, radius));
			float lower_glow = exp(-dot(iris - vec2(0.0, -0.78), iris - vec2(0.0, -0.78)) * 8.0);
			amber += mix(iris_tint, vec3(0.95, 0.88, 0.55), 0.54) * lower_glow * 0.62;
			vec2 pupil = abs(iris - vec2(0.0, 0.12));
			float pupil_shape = pupil.x / 0.29 + pupil.y / 0.50;
			amber = mix(amber, vec3(0.019, 0.012, 0.020), 1.0 - smoothstep(0.87, 1.08, pupil_shape));
			float sparkle = max(1.0 - smoothstep(0.16, 0.20, length(iris - vec2(-0.35, 0.36))),
				1.0 - smoothstep(0.075, 0.12, length(iris - vec2(0.30, -0.30))));
			eye_color = mix(eye_color, mix(amber, vec3(1.0, 0.93, 0.75), sparkle), iris_mask);
			float lash_shadow = smoothstep(-0.46, -0.06, lid_height);
			eye_color *= mix(vec3(1.0), vec3(0.72, 0.62, 0.63), lash_shadow);
			light = mix(light, eye_color * mix(0.84, 1.0, smoothstep(0.4, 0.8, cel_facing)), opening);
			vec4 liner = eyeMakeupLiner(lid, upper, lower);
			light = mix(light, liner.rgb, liner.a);
			float brow_x = eye_offset / 0.024;
			float brow_y = 0.386 + 0.0045 * (1.0 - brow_x * brow_x) - 0.0015 * brow_x;
			float brow = (1.0 - smoothstep(0.0007, 0.0018, abs(p.y - brow_y))) * (1.0 - smoothstep(0.77, 1.0, abs(brow_x)));
			light = mix(light, vec3(0.115, 0.059, 0.078), brow);
		}
	}
	if (part == 1) {
		float face_side = abs(p.x);
		float face_front = smoothstep(0.045, 0.065, p.z);
		float mouth_x = p.x / 0.015;
		float mouth_y = 0.311 + 0.0017 * mouth_x * mouth_x;
		float mouth = studioStroke(p.y - mouth_y, 0.00085) * (1.0 - smoothstep(0.62, 1.0, abs(mouth_x)));
		float nose_x = (face_side - 0.011) / 0.004;
		float nose_y = 0.332 + 0.0019 * nose_x;
		float nose = studioStroke(p.y - nose_y, 0.00065) * (1.0 - smoothstep(0.36, 1.0, abs(nose_x)));
		light = mix(light, vec3(0.26, 0.105, 0.097), face_front * max(0.48 * mouth, 0.36 * nose));
	}
	light = mix(light, flash.rgb, flash.a);
	ALBEDO = OUTPUT_IS_SRGB ? linear_to_srgb(light) : light;
}
