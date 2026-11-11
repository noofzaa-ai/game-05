// Small noise helpers shared by the effect shaders (brush edges, ink blots, cracks).

float vfx_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vfx_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(vfx_hash(i), vfx_hash(i + vec2(1.0, 0.0)), u.x),
		mix(vfx_hash(i + vec2(0.0, 1.0)), vfx_hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

// Smallest angle between two angles (radians), always positive.
float vfx_angle_gap(float a, float b) {
	float d = mod(a - b + 3.14159265, 6.2831853) - 3.14159265;
	return abs(d);
}
