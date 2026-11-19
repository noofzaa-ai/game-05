// Body of the particle-burst shader, shared by vfx_burst.gdshader (blend_mix) and vfx_burst_add.gdshader (blend_add).
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
uniform float drawn = 0.0;  // 1 = ink-wash look (client/vfx/ink_vfx.gd, graphics setting drawn_style)
uniform float pull = 0.0;  // meters drawn toward the camera (sparks at a hit point stay in front of the body)
// Violent skill looks (Boss 2026-11-19, scatter): style 3 = debris chunks that fly, fall, bounce once and lie on the
// floor until the end; style 4 = billowing smoke that rises, swells and lingers. ring = 1: particles leave sideways
// (azimuth all round, elevation `lift` +- spread/2) instead of in a cone, for a dust skirt along the ground.
uniform float floor_y = -100.0;  // the ground's height in the burst's own space (metres below its origin)
uniform float ring = 0.0;
uniform float lift = 0.0;  // radians above the ground for ring bursts

varying float v_alpha;
varying vec2 v_uv;
varying float v_rand;
varying float v_shade;

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
	if (ring > 0.5) {
		float el = lift + (rnd.y - 0.5) * spread;
		d = vec3(cos(el) * cos(phi), sin(el), cos(el) * sin(phi));
	}
	float life = style >= 3 ? mix(0.8, 1.0, r4) : mix(0.55, 1.0, r4);
	float t = progress * seconds;
	float local = t / (seconds * life);
	vec3 v0 = d * speed * mix(0.35, 1.0, r3);
	vec3 head = travel(v0, t);
	vec3 hv = (MODELVIEW_MATRIX * vec4(head, 1.0)).xyz;
	vec3 pos;
	v_shade = 1.0;
	if (style == 3) {  // a chunk: ballistic, one bounce, then it lies where it landed (no drag on the fall)
		float g = max(gravity, 0.5);
		float h0 = max(-floor_y, 0.0);
		float t_hit = (v0.y + sqrt(v0.y * v0.y + 2.0 * g * h0)) / g;
		vec3 hor0 = vec3(v0.x, 0.0, v0.z);
		float k = max(drag, 0.001);
		float tf = min(t, t_hit);
		vec3 p = hor0 * (1.0 - exp(-k * tf)) / k;
		p.y = v0.y * tf - 0.5 * g * tf * tf;
		float tb = max(t - t_hit, 0.0);
		float vb = 0.32 * abs(v0.y - g * t_hit);
		float t2 = 2.0 * vb / g;
		if (tb > 0.0) {
			float tbb = min(tb, t2);
			p.y = floor_y + vb * tbb - 0.5 * g * tbb * tbb;
			p += hor0 * exp(-k * t_hit) * 0.35 * (1.0 - exp(-5.0 * tb)) / 5.0;
		}
		float s = size * mix(0.45, 1.6, r3 * r3);
		p.y = max(p.y, floor_y) + s * 0.45;  // (a resting chunk sits on the floor, not half inside it)
		float ang = r4 * 6.2831853 + (r3 - 0.5) * 22.0 * min(t, t_hit + t2);
		vec2 c = UV - 0.5;
		vec2 rc = vec2(c.x * cos(ang) - c.y * sin(ang), c.x * sin(ang) + c.y * cos(ang));
		pos = (MODELVIEW_MATRIX * vec4(p, 1.0)).xyz + vec3(rc * s, 0.0);
		local = t / (seconds * life);
		v_shade = 0.75 + 0.5 * r4;
	} else if (style == 4) {  // smoke: swells fast, then slowly; rises on negative gravity; turns a little
		float grow = mix(0.45, 2.3, 1.0 - pow(1.0 - clamp(local, 0.0, 1.0), 2.2));
		float s = size * mix(0.7, 1.35, r3) * grow;
		float ang = r4 * 6.2831853 + local * (r3 - 0.5) * 1.5;
		vec2 c = UV - 0.5;
		vec2 rc = vec2(c.x * cos(ang) - c.y * sin(ang), c.x * sin(ang) + c.y * cos(ang));
		pos = hv + vec3(rc * s, 0.0);
		v_shade = mix(0.78, 1.08, r4);
	} else if (style == 0) {
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
	if (style == 3) {
		v_alpha = 1.0 - smoothstep(0.78, 1.0, local);  // debris stays, then fades at the end
	} else if (style == 4) {
		v_alpha = smoothstep(0.0, 0.06, local) * pow(1.0 - clamp(local, 0.0, 1.0), 1.3);
	}
	v_uv = UV;
	v_rand = r3;
}

void fragment() {
	float alpha;
	vec3 rgb = color.rgb;
	if (style == 3) {  // a rock: a faceted blob, lit from the top-left, with a dark edge
		vec2 p = v_uv * 2.0 - 1.0;
		float a = atan(p.y, p.x);
		float edge = 0.62 + 0.22 * vfx_noise(vec2(a * 1.6 + v_rand * 11.0, v_rand * 5.0));
		float r = length(p);
		alpha = step(r, edge);
		float lit = clamp(0.62 - 0.45 * p.y + 0.2 * p.x * -1.0, 0.25, 1.15);
		rgb = color.rgb * lit * v_shade;
		rgb = mix(rgb, ink_color.rgb, smoothstep(edge - 0.16, edge, r) * 0.75);
	} else if (style == 4) {  // smoke: a soft lumpy puff, darker underneath
		vec2 p = v_uv * 2.0 - 1.0;
		float r = length(p);
		float n = vfx_noise(p * 2.2 + v_rand * 19.0) * 0.6 + vfx_noise(p * 4.7 + v_rand * 7.0) * 0.4;
		alpha = smoothstep(1.0, 0.25, r + (n - 0.5) * 0.55) * 0.62;
		rgb = color.rgb * v_shade * mix(1.08, 0.72, clamp(p.y * 0.5 + 0.5, 0.0, 1.0));
		rgb = mix(rgb, ink_color.rgb, ink * (0.4 + 0.4 * n));
	} else if (style == 0) {
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
	float a_out = clamp(alpha * opacity * color.a, 0.0, 1.0);
	if (drawn > 0.5) {
		vec4 o = vfx_ink(rgb, a_out, v_uv, v_uv * 2.5 + v_rand * 13.0, ink_color.rgb);
		rgb = o.rgb;
		a_out = o.a;
	}
	if (a_out <= 0.004) {
		discard;
	}
	ALBEDO = rgb;
	ALPHA = a_out;
}
