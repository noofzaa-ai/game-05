shader_type spatial;
// A burst of sparks, ink drops, dust puffs or motes in ONE draw call: the mesh holds up to 32
// quads, each with its own random numbers baked in, and the vertex shader moves them (speed,
// spread cone, gravity, drag) from `progress`. No particle simulation on the CPU.
// style: 0 = streaks stretched along their motion (sparks), 1 = soft puffs that grow (dust, ink),
// 2 = small round glints (motes).
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled, blend_mix, skip_vertex_transform;

#include "res://client/vfx/vfx_common.gdshaderinc"

uniform int style = 0;
uniform vec4 color : source_color = vec4(1.0, 0.7, 0.2, 1.0);
uniform vec4 ink_color : source_color = vec4(0.06, 0.05, 0.08, 1.0);
uniform float ink = 0.0;
uniform float progress = 0.0;
uniform float seconds = 0.4;
uniform vec3 direction = vec3(0.0, 1.0, 0.0);
uniform float spread = 3.1416;  // half angle of the cone, radians (3.14 = every way)
uniform float speed = 4.0;
uniform float gravity = 9.0;
uniform float drag = 2.0;
uniform float size = 0.12;
uniform float count = 16.0;
uniform float streak = 0.05;  // seconds of motion each streak covers
uniform float seed = 0.0;
uniform float opacity = 1.0;
uniform float pull = 0.0;  // meters drawn toward the camera (sparks at a hit point stay in front of the body)

varying float v_alpha;
varying vec2 v_uv;
varying float v_rand;

vec3 travel(vec3 v0, float t) {
	return v0 * (1.0 - exp(-drag * t)) / max(drag, 0.001) + vec3(0.0, -0.5 * gravity * t * t, 0.0);
}

void vertex() {
	float index = floor(COLOR.r * 255.0 + 0.5);
	vec2 rnd = fract(UV2 + vec2(seed * 0.6180339, seed * 0.4142135));
	float r3 = fract(COLOR.g + seed * 0.2718281);
	float r4 = fract(COLOR.b + seed * 0.5772156);
	vec3 dir = normalize(direction + vec3(0.0, 0.0001, 0.0));
	vec3 up = abs(dir.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
	vec3 t1 = normalize(cross(up, dir));
	vec3 t2 = cross(dir, t1);
	float phi = rnd.x * 6.2831853;
	float cos_a = mix(1.0, cos(spread), rnd.y);
	float sin_a = sqrt(max(0.0, 1.0 - cos_a * cos_a));
	vec3 d = dir * cos_a + (t1 * cos(phi) + t2 * sin(phi)) * sin_a;
	float life = mix(0.55, 1.0, r4);
	float t = progress * seconds;
	float local = t / (seconds * life);
	vec3 v0 = d * speed * mix(0.35, 1.0, r3);
	vec3 head = travel(v0, t);
	vec3 hv = (MODELVIEW_MATRIX * vec4(head, 1.0)).xyz;
	vec3 pos;
	if (style == 0) {
		vec3 tv = (MODELVIEW_MATRIX * vec4(travel(v0, max(t - streak, 0.0)), 1.0)).xyz;
		vec2 dd = hv.xy - tv.xy;
		float len = length(dd);
		vec2 dn = len > 0.0001 ? dd / len : vec2(1.0, 0.0);
		vec2 perp = vec2(-dn.y, dn.x);
		pos = mix(tv, hv, UV.x);
		pos.xy += perp * (UV.y - 0.5) * size * (0.4 + 0.6 * (1.0 - local));
	} else {
		float grow = style == 1 ? mix(0.6, 1.7, clamp(local, 0.0, 1.0)) : (1.0 - 0.5 * clamp(local, 0.0, 1.0));
		float s = size * mix(0.7, 1.3, r3) * grow;
		pos = hv + vec3((UV - 0.5) * s, 0.0);
	}
	if (index >= count || local >= 1.0) {
		pos = vec3(0.0);  // unused or finished spark: a zero-size quad
	}
	pos.z += pull;
	VERTEX = pos;
	v_alpha = 1.0 - clamp(local, 0.0, 1.0);
	v_uv = UV;
	v_rand = r3;
}

void fragment() {
	float alpha;
	vec3 rgb = color.rgb;
	if (style == 0) {
		alpha = (1.0 - abs(v_uv.y * 2.0 - 1.0)) * mix(0.25, 1.0, v_uv.x);
		rgb = mix(color.rgb, vec3(1.0, 0.97, 0.85), v_uv.x * 0.55 * v_alpha);
	} else {
		vec2 p = v_uv * 2.0 - 1.0;
		float r = length(p);
		if (style == 1) {
			float n = vfx_noise(p * 2.5 + v_rand * 17.0);
			alpha = smoothstep(1.0, 0.55 - 0.25 * n, r + 0.15 * n) * 0.8;
			rgb = mix(color.rgb, ink_color.rgb, ink * (0.6 + 0.4 * n));
		} else {
			alpha = pow(clamp(1.0 - r, 0.0, 1.0), 1.5);
			rgb = mix(color.rgb, vec3(1.0), alpha * 0.6);
		}
	}
	alpha *= v_alpha;
	if (alpha <= 0.004) {
		discard;
	}
	ALBEDO = rgb;
	ALPHA = clamp(alpha * opacity * color.a, 0.0, 1.0);
}
