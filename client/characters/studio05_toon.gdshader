shader_type spatial;
// Character Artist, zorx. Port of the studio05 Studio (v20261111: index.html applyCelShading,
// eyes/anime-face.js, eyes/eye-makeup.js, eyes/iris-presets.js, line-art.js).
// Target: Compatibility renderer (web/mobile). One shader for body, face, hair and class gear.
// Cel bands use the Studio's fixed camera-space key; colours are linear.
// Bind-pose positions (GLB units) of the UV-less head/hair A-F are baked into UV (x, y) and UV2 (z) at load,
// because VERTEX here is post-skinning. Textured gear and Hair G keep their real UV (has_rest = false).
render_mode unshaded, cull_disabled, fog_disabled;

group_uniforms surface;
uniform vec3 base_color_linear = vec3(0.72, 0.56, 0.48); // material colour (three.js material.color)
uniform bool use_albedo_tex = false; // class gear / Hair G: baseColorTexture
// No source_color hint: the Compatibility renderer returns the raw sRGB texels for a source_color
// sampler (no decode) while the shader still encodes its linear result below, which double-encoded the
// gear texture (washed-out pink-grey armor). Decoded by hand here so it is the same on every renderer
// (three.js decodes baseColorTexture as sRGB before the multiply).
uniform sampler2D albedo_tex : filter_linear_mipmap, repeat_enable;
uniform bool use_normal_tex = false; // class gear / Hair G: normalTexture (perturbs the cel normal)
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform bool use_vertex_color = false; // COLOR_0 multiplies the colour (Hair C-F)
uniform vec4 flash = vec4(0.0); // game tint (hit flash etc.): rgb, a = strength
group_uniforms;

group_uniforms face;
uniform int part = 0; // 0 body/outfit/gear, 1 face (Head_Anime), 2 hair
uniform bool has_rest = false;
uniform vec3 iris_tint = vec3(0.5776, 0.2384, 0.0331); // #C98634 in linear
uniform int iris_style = 0; // Studio menu value: 0 Classic, 1 Starry Violet, 3, 6, 7, 9, 10
uniform int makeup_style = 0; // 0 Anime Soft, 1 Sharp Wing, 2 Natural (no makeup)
uniform float blink = 0.0; // 0 open .. 1 shut (eyes/blink.js)
uniform bool eyes_visible = true;
group_uniforms;

group_uniforms hair;
uniform float hair_part = -0.003;
uniform float painted_bangs = 0.0;
group_uniforms;

// Card-only ink-wash look (Technical Artist, hub ink-wash direction 2026-11-14). Off everywhere except the
// class card portraits (studio05_character_model.gd card_ink): battle and the Studio parity look are unchanged.
// A uniform branch (same value for every pixel of a draw), so the cost off-card is one compare.
group_uniforms card_ink;
uniform bool card_ink = false;
uniform vec3 card_shadow_tint = vec3(0.90, 0.74, 0.68); // warm paper shadow (multiplies, instead of grey darkening)
uniform float card_band_light = 1.10; // lit band level
uniform float card_band_mid = 1.0; // (unused since 2-band cel; kept for tuning)
uniform float card_band_dark = 0.78; // shadow band level (times card_shadow_tint)
uniform float card_desaturate = 0.06; // 0..1 toward luminance: the watercolour palette
uniform vec3 card_paper = vec3(0.86, 0.80, 0.68); // paper tone washed over the colours (linear)
uniform float card_paper_wash = 0.035; // how much of the paper tone shows through
uniform float card_grain = 0.045; // paper-grain multiply strength (screen space, 0 = off)
uniform float card_grain_pixels = 3.0; // grain cell size in pixels
uniform vec3 card_ink_color = vec3(0.010, 0.0045, 0.0025); // inner line ink (same brown as card_ink_hull)
uniform float card_rim_ink = 0.8; // ink where the surface turns away (face edge, arm and fold edges)
uniform float card_crease_ink = 0.7; // ink where the normal bends sharply (folds, hair locks, weapon edges)
uniform float card_band_ink = 0.55; // a thin line along the shadow edge (drawn cel)
group_uniforms;

// Studio key light (camera space) and cel levels, STUDIO_SPEC.md.
const vec3 CEL_KEY = vec3(-0.45, 0.65, 0.72);
const float CEL_DARK = 0.63;
const float CEL_MID = 0.88;
const float CEL_LIGHT = 1.08;

varying vec3 rest_pos;
varying vec4 vertex_color;

void vertex() {
	rest_pos = has_rest ? vec3(UV.x, UV.y, UV2.x) : VERTEX;
	vertex_color = COLOR;
}

float studioStroke(float d, float half_width) {
	float aa = clamp(0.5 * fwidth(d), 0.0002, 0.0025);
	return 1.0 - smoothstep(half_width - aa, half_width + aa, abs(d));
}

// ---- eyes/eye-makeup.js
float lashTip(vec2 eye, vec2 root, vec2 tip, float root_width) {
	vec2 axis = tip - root;
	float along = dot(eye - root, axis) / dot(axis, axis);
	float across = length(eye - root - along * axis);
	float width = root_width * (1.0 - clamp(along, 0.0, 1.0));
	return (1.0 - smoothstep(width - 0.025, width + 0.025, across))
		* smoothstep(-0.15, 0.0, along) * (1.0 - smoothstep(0.92, 1.0, along));
}

vec4 eyeMakeupShadow(vec2 lid, float lid_height) {
	if (makeup_style == 2) {
		return vec4(0.0);
	}
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

vec4 eyeMakeupLiner(vec2 lid, float upper, float lower, float shut, vec3 skin_color) {
	if (makeup_style == 2) {
		// Skin-toned crease along the socket, softer below.
		float span = 1.0 - smoothstep(0.83, 1.0, abs(lid.x));
		float top = (1.0 - smoothstep(0.018, 0.063, abs(lid.y - upper))) * 0.73;
		float bottom = (1.0 - smoothstep(0.012, 0.051, abs(lid.y - lower))) * 0.40;
		return vec4(skin_color * vec3(0.46, 0.42, 0.40), span * max(top, bottom));
	}
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
		float coverage = max(span * max(upper_ink, lower_ink), wing * (1.0 - shut));
		return vec4(vec3(0.043, 0.017, 0.026), coverage);
	}
	float lash_width = mix(0.14, 0.30, smoothstep(0.05, 0.86, lid.x));
	float lash = (1.0 - smoothstep(lash_width - 0.04, lash_width + 0.04, abs(lid.y - upper)))
		* (1.0 - smoothstep(0.94, 1.05, abs(lid.x)));
	float wing = lashTip(lid, vec2(0.70, 0.62), vec2(1.20, 0.90), 0.16);
	wing = max(wing, lashTip(lid, vec2(0.82, 0.47), vec2(1.26, 0.61), 0.13));
	wing = max(wing, lashTip(lid, vec2(0.91, 0.32), vec2(1.22, 0.35), 0.10));
	wing *= 1.0 - shut;
	float lower_width = mix(0.035, 0.17, smoothstep(0.64, 0.96, lid.x));
	float lower_lash = (1.0 - smoothstep(lower_width * 0.5, lower_width + 0.04, abs(lid.y - lower)))
		* (1.0 - smoothstep(0.95, 1.025, abs(lid.x)));
	float lower_opacity = mix(0.32, 0.92, smoothstep(0.42, 0.93, lid.x));
	return vec4(vec3(0.042, 0.017, 0.026), max(max(lash, wing), lower_opacity * lower_lash));
}

// ---- eyes/anime-face.js + eyes/iris-presets.js
float irisSpark(vec2 point, vec2 center, float size) {
	return 1.0 - smoothstep(size * 0.65, size, length(point - center));
}

float irisOval(vec2 point, vec2 center, vec2 axes) {
	return 1.0 - smoothstep(0.9, 1.04, length((point - center) / axes));
}

vec3 starryIris(vec2 point, float radius) {
	vec3 night = mix(vec3(0.018, 0.010, 0.04), iris_tint, 0.10);
	vec3 glow = mix(iris_tint, vec3(0.91, 0.68, 0.97), 0.32);
	vec3 color = mix(night, glow, 1.0 - smoothstep(-0.84, 0.35, point.y));
	color = mix(color, night * 0.50, smoothstep(0.90, 1.0, radius) * 0.75);
	float slit = length((point - vec2(0.0, 0.05)) / vec2(0.145, 0.56));
	color = mix(color, vec3(0.009, 0.006, 0.019), 1.0 - smoothstep(0.95, 1.05, slit));
	float reflection = length((point - vec2(-0.035, 0.12)) / vec2(0.082, 0.45));
	float stars = 1.0 - smoothstep(0.90, 1.04, reflection);
	stars = max(stars, irisSpark(point, vec2(-0.53, 0.36), 0.12));
	stars = max(stars, irisSpark(point, vec2(0.54, 0.28), 0.095));
	stars = max(stars, irisSpark(point, vec2(-0.43, -0.36), 0.058));
	stars = max(stars, irisSpark(point, vec2(0.29, -0.60), 0.064));
	stars = max(stars, irisSpark(point, vec2(0.58, -0.21), 0.045));
	return mix(color, vec3(1.0, 0.91, 1.0), stars);
}

vec3 solarFlameIris(vec2 point, float radius) {
	vec3 ember = iris_tint * 0.20 + vec3(0.013, 0.003, 0.004);
	vec3 flame = mix(iris_tint, vec3(1.0, 0.77, 0.27), 0.67);
	float angle = atan(point.y, point.x + 0.0001);
	float tongues = sin(angle * 11.0 + radius * 3.0) * 0.10 + sin(angle * 19.0 - radius * 4.0) * 0.055;
	vec3 color = mix(iris_tint * 0.78, flame, 1.0 - smoothstep(-0.50, 0.05, point.y + tongues));
	color = mix(color, ember, smoothstep(0.12, 0.40, point.y));
	float corona = smoothstep(0.56, 0.70, radius) * (1.0 - smoothstep(0.79, 0.90, radius));
	corona *= smoothstep(0.04, 0.23, point.y) * smoothstep(-0.82, -0.36, point.x);
	color = mix(color, iris_tint * 1.22, corona);
	float pupil = irisOval(point, vec2(0.015, 0.04), vec2(0.14, 0.42));
	pupil = max(pupil, irisOval(point, vec2(0.17, 0.25), vec2(0.26, 0.13)) * smoothstep(0.02, 0.24, point.y));
	color = mix(color, ember * 0.42, pupil);
	float shine = irisOval(point, vec2(-0.29, 0.46), vec2(0.14, 0.082));
	return mix(color, vec3(1.0, 0.94, 0.73), shine);
}

vec3 lavenderOrbitIris(vec2 point, float radius) {
	vec3 violet = mix(iris_tint, vec3(0.90, 0.81, 0.99), 0.30);
	vec3 color = mix(violet, iris_tint * 0.40, smoothstep(-0.06, 0.73, point.y));
	color = mix(color, mix(violet, vec3(0.98, 0.91, 1.0), 0.58),
		smoothstep(0.10, 0.82, radius) * (1.0 - smoothstep(-0.33, 0.08, point.y)));
	float orbit = (1.0 - smoothstep(0.035, 0.075, abs(length(point - vec2(-0.07, 0.02)) - 0.49)))
		* smoothstep(-0.25, 0.18, point.y);
	color = mix(color, iris_tint * 0.29, orbit * 0.80);
	float pupil = irisOval(point, vec2(-0.015, 0.01), vec2(0.238, 0.26));
	color = mix(color, vec3(0.026, 0.016, 0.058), pupil);
	float shine = irisOval(point, vec2(0.26, 0.54), vec2(0.25, 0.13));
	shine = max(shine, irisSpark(point, vec2(-0.48, -0.21), 0.063));
	shine = max(shine, irisSpark(point, vec2(0.40, -0.11), 0.053));
	shine = max(shine, irisSpark(point, vec2(-0.30, 0.44), 0.042));
	return mix(color, vec3(0.98, 0.92, 1.0), shine * 0.94);
}

vec3 sunburstIris(vec2 point, float radius) {
	vec3 coral = mix(iris_tint, vec3(1.0, 0.65, 0.51), 0.48);
	vec3 color = mix(coral, iris_tint * 0.87, smoothstep(-0.67, 0.35, point.y));
	vec2 orb = (point - vec2(-0.07, 0.03)) / vec2(0.56, 0.60);
	float orb_radius = length(orb);
	vec3 light = mix(vec3(1.0, 0.96, 0.81), mix(iris_tint, vec3(1.0, 0.89, 0.37), 0.82), smoothstep(-0.32, 0.82, orb.y));
	color = mix(color, light, 1.0 - smoothstep(0.92, 1.02, orb_radius));
	float crescent = smoothstep(0.81, 0.88, radius) * smoothstep(-0.02, 0.72, -point.y - point.x * 0.38);
	color = mix(color, vec3(1.0, 0.91, 0.82), crescent * 0.84);
	float shine = irisOval(point, vec2(0.31, 0.54), vec2(0.16, 0.095));
	return mix(color, vec3(1.0, 0.98, 0.83), shine);
}

vec3 pastelHaloIris(vec2 point, float radius) {
	vec3 lilac = mix(iris_tint, vec3(0.89, 0.69, 0.98), 0.53);
	vec3 color = mix(lilac, iris_tint * 0.46, smoothstep(-0.26, 0.50, point.y));
	float halo = smoothstep(0.57, 0.72, radius) * (1.0 - smoothstep(0.77, 0.83, radius));
	color = mix(color, lilac * 1.24, halo * smoothstep(0.02, 0.40, point.y) * 0.48);
	float glow = irisOval(point, vec2(0.11, -0.78), vec2(0.48, 0.25));
	color = mix(color, mix(lilac, vec3(1.0, 0.91, 0.52), 0.81), glow);
	float pupil_border = irisOval(point, vec2(0.015, 0.07), vec2(0.33, 0.38));
	float pupil_light = irisOval(point, vec2(0.015, 0.07), vec2(0.28, 0.33));
	color = mix(color, iris_tint * 0.18, pupil_border);
	color = mix(color, vec3(0.98, 0.91, 1.0), pupil_light);
	float shine = irisSpark(point, vec2(0.43, 0.48), 0.105);
	shine = max(shine, irisSpark(point, vec2(0.61, 0.35), 0.065));
	shine = max(shine, irisSpark(point, vec2(-0.49, -0.21), 0.043));
	return mix(color, vec3(1.0, 0.94, 1.0), shine);
}

vec3 astralSigilIris(vec2 point, float radius) {
	vec3 pink = mix(iris_tint, vec3(0.94, 0.52, 0.83), 0.60);
	vec3 color = mix(pink, iris_tint * 0.48, smoothstep(0.04, 0.14, point.y + point.x * 0.23));
	float angle = atan(point.y, point.x + 0.0001);
	float rays = smoothstep(0.73, 0.95, sin(angle * 29.0)) * smoothstep(0.45, 0.88, radius);
	color += pink * rays * smoothstep(0.07, 0.26, point.y) * 0.31;
	vec2 ring = (point - vec2(-0.05, -0.22)) / vec2(0.74, 0.46);
	float ring_radius = length(ring);
	float ring_line = 1.0 - smoothstep(0.017, 0.053, abs(ring_radius - 0.98));
	float ring_angle = atan(ring.y, ring.x + 0.0001);
	float ticks = smoothstep(0.75, 0.94, cos(ring_angle * 19.0))
		* smoothstep(0.88, 0.94, ring_radius) * (1.0 - smoothstep(1.05, 1.14, ring_radius));
	color = mix(color, mix(pink, vec3(1.0), 0.64), max(ring_line, ticks) * 0.77);
	float pupil = irisOval(point, vec2(0.015, 0.08), vec2(0.133, 0.21));
	color = mix(color, iris_tint * 0.13, pupil);
	color = mix(color, pink * 0.72, irisOval(point, vec2(0.015, 0.08), vec2(0.075, 0.143)));
	float shine = irisOval(point, vec2(0.38, 0.51), vec2(0.15, 0.092));
	shine = max(shine, irisSpark(point, vec2(0.22, 0.39), 0.067));
	return mix(color, vec3(1.0, 0.94, 1.0), shine);
}

vec3 referenceIris(vec2 point, float radius) {
	vec3 color;
	if (iris_style == 3) {
		color = solarFlameIris(point, radius);
	} else if (iris_style == 6) {
		color = lavenderOrbitIris(point, radius);
	} else if (iris_style == 7) {
		color = sunburstIris(point, radius);
	} else if (iris_style == 9) {
		color = pastelHaloIris(point, radius);
	} else {
		color = astralSigilIris(point, radius);
	}
	return mix(color, iris_tint * 0.19, smoothstep(0.90, 1.0, radius) * 0.78);
}

// Upper and lower rim in metres, sampled from the nose side to the temple.
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

// Value noise for the paper grain (cheap: 4 hashes, no texture read).
float cardHash(vec2 cell) {
	return fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453);
}

float cardGrain(vec2 pixel) {
	vec2 cell = floor(pixel);
	vec2 f = fract(pixel);
	f = f * f * (3.0 - 2.0 * f);
	float a = cardHash(cell);
	float b = cardHash(cell + vec2(1.0, 0.0));
	float c = cardHash(cell + vec2(0.0, 1.0));
	float d = cardHash(cell + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

vec3 srgb_to_linear(vec3 c) {
	return mix(c / 12.92, pow((max(c, vec3(0.0)) + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

vec3 linear_to_srgb(vec3 v) {
	vec3 low = 12.92 * v;
	vec3 high = 1.055 * pow(max(v, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055;
	return mix(low, high, step(vec3(0.0031308), v));
}

void fragment() {
	vec3 n = normalize(NORMAL);
	if (use_normal_tex) {
		// Same tangent-space mix as Godot's StandardMaterial normal map (depth 1).
		vec2 nm = texture(normal_tex, UV).xy * 2.0 - 1.0;
		float nz = sqrt(max(0.0, 1.0 - dot(nm, nm)));
		n = normalize(TANGENT * nm.x + BINORMAL * nm.y + NORMAL * nz);
	}
	if (!FRONT_FACING) {
		n = -n;
	}
	vec3 diffuse = base_color_linear;
	if (use_albedo_tex) {
		diffuse *= srgb_to_linear(texture(albedo_tex, UV).rgb);
	}
	if (use_vertex_color) {
		diffuse *= vertex_color.rgb;
	}
	float cel_facing = dot(n, normalize(CEL_KEY));
	float band = mix(CEL_DARK, CEL_MID, smoothstep(0.05, 0.09, cel_facing));
	band = mix(band, CEL_LIGHT, smoothstep(0.56, 0.60, cel_facing));
	vec3 light = diffuse * band;
	if (card_ink) {
		// Two crisp flat cel bands; the shadow is a warm paper-tinted wash, not a grey darkening.
		float shade = 1.0 - smoothstep(0.10, 0.13, cel_facing);
		light = diffuse * mix(vec3(card_band_light), card_shadow_tint * card_band_dark, shade);
	}
	vec3 p = rest_pos;

	if (part == 2) {
		// line-art.js hairInk
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
		vec3 ink_color = mix(diffuse * 0.19, vec3(0.009, 0.006, 0.018), 0.5);
		light = mix(light, ink_color, max(crease_ink * 0.50, max(band_ink * 0.52, bang_ink * 0.64)));
	}

	if (part == 1 && eyes_visible) {
		// anime-face.js faceLayers: bind-pose head coordinates, so the artwork follows skinning.
		float side = abs(p.x);
		if (p.z > 0.015 && side < 0.074 && p.y > 0.334 && p.y < 0.415) {
			float socket_t = (side - 0.021) / 0.0445;
			float socket_position = clamp(socket_t, 0.0, 1.0);
			float socket_base = mix(0.359, 0.361, socket_position);
			vec2 lid = vec2(2.0 * socket_t - 1.0, (p.y - socket_base) / 0.013);
			vec2 rim = (eyeSocketRim(socket_t) + (0.001 - 0.002 * socket_position) - socket_base) / 0.013;
			// A relaxed lid covers a little of the upper iris without moving the socket corners.
			float lid_center = max(0.0, 1.0 - lid.x * lid.x);
			rim.x -= 0.065 * lid_center;
			float shut = clamp(blink, 0.0, 1.0);
			float closed_lid = mix(rim.y, rim.x, 0.24);
			float upper = mix(rim.x, closed_lid, shut);
			float lower = mix(rim.y, closed_lid, shut);
			float lid_height = lid.y - upper;
			vec3 skin_color = light;
			bool natural_lids = makeup_style == 2;
			vec4 shadow = eyeMakeupShadow(lid, lid_height);
			light = mix(light, shadow.rgb, shadow.a * (1.0 - 0.7 * shut));

			float opening = smoothstep(-0.04, 0.04, min(1.0 - abs(lid.x), min(upper - lid.y, lid.y - lower)))
				* (1.0 - smoothstep(0.96, 1.0, shut));
			vec3 eye_color = vec3(0.96, 0.87, 0.76);
			// Gaze centred in each socket; round pupils.
			vec2 iris = (vec2(side, p.y) - vec2(0.04325, 0.3585)) / 0.0123;
			iris.x *= sign(p.x);
			float radius = length(iris);
			float iris_mask = 1.0 - smoothstep(0.94, 1.01, radius);
			vec3 amber = mix(min(iris_tint * 1.35, vec3(1.0)), iris_tint * 0.24, smoothstep(-0.72, 0.6, iris.y));
			float glint = sin(atan(iris.y, iris.x + 0.0001) * 19.0) * 0.5 + 0.5;
			amber += mix(iris_tint, vec3(1.0), 0.3) * 0.37 * glint * smoothstep(0.35, 0.9, radius) * (1.0 - smoothstep(-0.50, 0.35, iris.y));
			amber = mix(amber, iris_tint * 0.20, smoothstep(0.82, 0.98, radius));
			float lower_glow = exp(-dot(iris - vec2(0.0, -0.78), iris - vec2(0.0, -0.78)) * 8.0);
			amber += mix(iris_tint, vec3(0.95, 0.88, 0.55), 0.54) * lower_glow * 0.62;
			float pupil_shape = length(iris - vec2(0.0, 0.07)) / 0.35;
			amber = mix(amber, vec3(0.019, 0.012, 0.020), 1.0 - smoothstep(0.87, 1.08, pupil_shape));
			float sparkle = max(1.0 - smoothstep(0.16, 0.20, length(iris - vec2(-0.35, 0.36))),
				1.0 - smoothstep(0.075, 0.12, length(iris - vec2(0.30, -0.30))));
			vec3 iris_color = mix(amber, vec3(1.0, 0.93, 0.75), sparkle);
			if (iris_style == 1) {
				iris_color = starryIris(iris, radius);
			} else if (iris_style > 1 && iris_mask > 0.0) {
				iris_color = referenceIris(iris, radius);
			}
			eye_color = mix(eye_color, iris_color, iris_mask);
			float lash_shadow = smoothstep(-0.46, -0.06, lid_height);
			vec3 lid_shade = natural_lids ? vec3(0.90, 0.88, 0.87) : vec3(0.72, 0.62, 0.63);
			eye_color *= mix(vec3(1.0), lid_shade, lash_shadow);
			light = mix(light, eye_color * mix(0.84, 1.0, smoothstep(0.4, 0.8, cel_facing)), opening);

			vec4 liner = eyeMakeupLiner(lid, upper, lower, shut, skin_color);
			float shut_line = studioStroke(lid.y - closed_lid, natural_lids ? 0.038 : 0.065)
				* (1.0 - smoothstep(0.91, 1.02, abs(lid.x)))
				* (natural_lids ? 0.80 : 1.0);
			float close_blend = smoothstep(0.62, 0.97, shut);
			light = mix(light, liner.rgb, mix(liner.a, shut_line, close_blend));

			float brow_x = (side - 0.039) / 0.024;
			float brow_y = 0.386 + 0.0045 * (1.0 - brow_x * brow_x) - 0.00075 * brow_x;
			float brow = (1.0 - smoothstep(0.0007, 0.0018, abs(p.y - brow_y))) * (1.0 - smoothstep(0.77, 1.0, abs(brow_x)));
			light = mix(light, vec3(0.115, 0.059, 0.078), brow);
		}
	}
	if (part == 1) {
		// line-art.js faceInk
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
	if (card_ink) {
		// Watercolour palette: a little desaturated, a thin paper wash, paper grain multiplied in.
		float luma = dot(light, vec3(0.2126, 0.7152, 0.0722));
		light = mix(light, vec3(luma), card_desaturate);
		light = mix(light, card_paper * max(luma * 1.6, 0.35), card_paper_wash);
		float grain = cardGrain(FRAGCOORD.xy / card_grain_pixels) * 0.6 + cardGrain(FRAGCOORD.xy / (card_grain_pixels * 4.0)) * 0.4;
		light *= 1.0 - card_grain * grain;
		// Drawn inner lines (screen-space derivatives, no extra pass): the rim where the surface turns away
		// from the eye, sharp normal bends, and a thin stroke along the shadow edge.
		vec3 view_n = normalize(NORMAL) * (FRONT_FACING ? 1.0 : -1.0);
		float facing = abs(dot(view_n, normalize(VIEW)));
		float rim = 1.0 - smoothstep(0.07, 0.15, facing);
		float crease = smoothstep(0.35, 0.70, max(length(dFdx(view_n)), length(dFdy(view_n))));
		float edge_slope = max(fwidth(cel_facing), 0.0001);
		float band_edge = (1.0 - smoothstep(0.5, 1.4, abs(cel_facing - 0.115) / edge_slope)) * smoothstep(0.01, 0.06, edge_slope);
		float ink = max(rim * card_rim_ink, max(crease * card_crease_ink, band_edge * card_band_ink));
		if (part == 1) {
			ink *= 1.0 - smoothstep(0.03, 0.05, rest_pos.z) * 0.85; // keep the face itself clean (eyes, mouth)
		}
		light = mix(light, card_ink_color, ink);
	}
	light = mix(light, flash.rgb, flash.a);
	ALBEDO = OUTPUT_IS_SRGB ? linear_to_srgb(light) : light;
}
