shader_type canvas_item;
render_mode blend_add;
// Holographic foil overlay for the active class card (web-safe: one quad, a few maths ops, no texture reads).
// Drawn over the whole card, clipped to its rounded corners. `tilt` is the smoothed pointer offset (-1..1).

group_uniforms motion;
uniform vec2 tilt = vec2(0.0);
uniform float time = 0.0;
uniform float intensity : hint_range(0.0, 1.0) = 1.0; // fades the whole effect in and out
group_uniforms;

group_uniforms shape;
uniform vec2 rect_size = vec2(300.0, 420.0); // pixels, set from the card
uniform float corner_radius = 22.0;          // pixels
group_uniforms;

group_uniforms strengths;
uniform float sheen_strength : hint_range(0.0, 1.0) = 0.3;   // soft glow that follows the tilt
uniform float rainbow_strength : hint_range(0.0, 1.0) = 0.22; // iridescent band
uniform float streak_strength : hint_range(0.0, 1.0) = 0.45; // specular streak
uniform float edge_strength : hint_range(0.0, 1.0) = 0.55;   // glint on the card border
uniform float streak_width : hint_range(0.01, 0.5) = 0.07;
uniform float edge_width = 7.0;                               // pixels
uniform float rainbow_scale : hint_range(0.5, 8.0) = 2.5;
group_uniforms;

vec3 hue(float h) {
	// cheap hue wheel
	vec3 k = clamp(abs(fract(vec3(h) + vec3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
	return k;
}

void fragment() {
	vec2 p = UV * rect_size;
	// signed distance to the rounded rectangle: negative inside
	vec2 q = abs(p - rect_size * 0.5) - (rect_size * 0.5 - vec2(corner_radius));
	float d = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - corner_radius;
	float mask = 1.0 - smoothstep(-1.0, 0.5, d);

	// position along the diagonal; the streak centre slides with the tilt
	float s = dot(UV - 0.5, vec2(0.7071, 0.7071));
	float centre = tilt.x * 0.45 + tilt.y * 0.3 + sin(time * 0.4) * 0.03;
	float off = (s - centre);

	float streak = exp(-pow(off / streak_width, 2.0)) * streak_strength;
	float band = 0.35 + 0.65 * exp(-pow(off / 0.35, 2.0));
	vec3 rainbow = hue(s * rainbow_scale + tilt.x * 0.6 + tilt.y * 0.4 + time * 0.03) * rainbow_strength * band;
	float sheen = exp(-length(UV - (vec2(0.5) + tilt * 0.35)) * 3.0) * sheen_strength;
	float edge = (1.0 - smoothstep(0.0, edge_width, -d)) * (0.25 + 0.75 * exp(-pow(off / 0.25, 2.0))) * edge_strength;

	vec3 col = vec3(streak + sheen + edge) + rainbow;
	COLOR = vec4(col, mask * intensity);
}
