shader_type canvas_item;
// World map (client/hub_world_map_panel.gd): the archipelago image toned down toward the ink hub (less colour, a
// warm paper tint) and a drifting slate fog over every zone that is not open; `holes` are the open zones' centres
// (UV), unused slots sit off the image.
uniform float saturation = 0.55;
uniform vec3 paper = vec3(0.93, 0.86, 0.72);
uniform vec2 holes[8];
uniform vec2 hole_radius = vec2(0.13, 0.17);
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1)), f.x), f.y);
}
void fragment() {
	vec4 base = texture(TEXTURE, UV);
	float gray = dot(base.rgb, vec3(0.2126, 0.7152, 0.0722));
	base.rgb = mix(vec3(gray), base.rgb, saturation) * mix(vec3(1.0), paper, 0.35);
	float n = noise(UV * 18.0) * 0.6 + noise(UV * 43.0) * 0.3 + noise(UV * 91.0) * 0.1;
	float d = 9.0;
	for (int i = 0; i < 8; i++) {
		d = min(d, length((UV - holes[i]) / hole_radius));
	}
	float reveal = 1.0 - smoothstep(0.83 + n * 0.13, 1.07 + n * 0.13, d);
	vec3 fog = mix(vec3(0.16, 0.15, 0.17), vec3(0.42, 0.40, 0.38), n);
	vec3 hidden = mix(base.rgb * 0.3, fog, 0.82);
	COLOR = vec4(mix(hidden, base.rgb, reveal), base.a);
}
