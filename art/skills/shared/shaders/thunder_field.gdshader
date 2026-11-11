shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;
uniform vec4 tint : source_color = vec4(0.02,0.075,0.19,0.24);
uniform float cast_time = 0.0;
uniform float impact_time = 1.12;
uniform float opacity = 1.0;
uniform float energy = 0.04;
uniform float surface_kind = 4.0;
void fragment() {
	float radial=length(UV-vec2(0.5))*2.0;
	float age=max(0.0,cast_time-impact_time);
	float pulse=0.5+0.5*sin(radial*16.0-age*5.0);
	ALBEDO=mix(vec3(0.005,0.013,0.055),vec3(0.018,0.08,0.22),pulse);
	EMISSION=ALBEDO*energy;
	ALPHA=tint.a*opacity*(1.0-smoothstep(0.73,1.02,radial));
}
