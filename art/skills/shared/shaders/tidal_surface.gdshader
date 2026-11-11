shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;

uniform vec4 tint : source_color = vec4(0.05, 0.55, 0.95, 0.82);
uniform float cast_time = 0.0;
uniform float impact_time = 1.12;
uniform float opacity = 1.0;
uniform float surface_kind = 0.0; // water0, foam1, flash2, drop3, pool4, flight5
uniform float energy = 0.5;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1,311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i=floor(p), f=fract(p), u=f*f*(3.0-2.0*f);
	return mix(mix(hash(i),hash(i+vec2(1.0,0.0)),u.x),
		mix(hash(i+vec2(0.0,1.0)),hash(i+vec2(1.0,1.0)),u.x),u.y);
}
void fragment() {
	float age=max(0.0,cast_time-impact_time);
	float flow=noise(UV*vec2(15.0,4.0)+vec2(age*0.7,-age*1.9));
	float mask=1.0;
	vec3 color=tint.rgb;
	if (surface_kind < 0.5) {
		float foam=smoothstep(0.64,0.9,flow+UV.y*0.20);
		color=mix(vec3(0.015,0.24,0.53),vec3(0.10,0.70,0.95),flow);
		color=mix(color,vec3(0.55,0.88,0.97),foam*0.60);
		mask=smoothstep(0.0,0.04,UV.y)*(1.0-smoothstep(0.88,1.02,UV.y+(0.5-flow)*0.08));
	} else if (surface_kind < 1.5) {
		color=mix(vec3(0.23,0.75,0.93),vec3(0.85,0.99,1.0),flow);
		mask=0.65+0.35*smoothstep(0.26,0.64,flow);
	} else if (surface_kind > 3.5 && surface_kind < 4.5) {
		color=mix(vec3(0.012,0.19,0.29),vec3(0.025,0.43,0.56),flow);
		float radial=length(UV-vec2(0.5))*2.0;
		mask=1.0-smoothstep(0.72,1.02,radial);
	} else if (surface_kind > 2.5 && surface_kind < 3.5) {
		float facing=abs(dot(normalize(NORMAL),normalize(VIEW)));
		color=mix(tint.rgb,vec3(0.88,0.99,1.0),pow(1.0-facing,2.0)*0.85);
	}
	ALBEDO=color;
	EMISSION=color*energy;
	// Open splash sheets show both sides; the back wall remains subordinate.
	float back_wall=(!FRONT_FACING && surface_kind < 1.5) ? 0.34 : 1.0;
	ALPHA=clamp(tint.a*opacity*mask*back_wall,0.0,1.0);
}
