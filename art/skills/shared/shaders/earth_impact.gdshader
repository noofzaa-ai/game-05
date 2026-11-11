shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;

uniform vec4 tint : source_color = vec4(0.84,0.66,0.38,1.0);
uniform float cast_time = 0.0;
uniform float impact_time = 1.12;
uniform float opacity = 1.0;
uniform float surface_kind = 0.0; // flash 0, flight 1, cracks 2, rim/ripples 3, ground 4
varying vec3 ground_position;

void vertex() { ground_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p) {
	vec2 i=floor(p),f=fract(p),u=f*f*(3.0-2.0*f);
	return mix(mix(hash(i),hash(i+vec2(1.0,0.0)),u.x),mix(hash(i+vec2(0.0,1.0)),hash(i+vec2(1.0,1.0)),u.x),u.y);
}
void fragment() {
	float age=max(0.0,cast_time-impact_time);
	float n=noise(ground_position.xz*3.1);
	float mask=1.0;
	vec3 color=tint.rgb;
	float energy=0.0;
	if (surface_kind<0.5) {
		color=vec3(1.0,0.90,0.67);
		energy=1.4;
	} else if (surface_kind<1.5) {
		mask=pow(max(0.0,1.0-abs(UV.y-0.5)*2.0),0.65);
		mask*=0.45+0.55*noise(vec2(UV.x*25.0,cast_time*5.0));
		color=vec3(0.92,0.82,0.55);
		energy=0.55;
	} else if (surface_kind<2.5) {
		color=mix(vec3(0.24,0.14,0.065),vec3(0.64,0.44,0.19),n);
		energy=0.07*(1.0-smoothstep(0.10,0.55,age));
	} else if (surface_kind<3.5) {
		mask=sin(clamp(UV.y,0.0,1.0)*3.14159)*(0.70+0.30*n);
		color=mix(vec3(0.48,0.31,0.14),vec3(0.84,0.67,0.38),n);
	} else {
		float radius=length(UV-vec2(0.5))*2.0;
		mask=1.0-smoothstep(0.70,1.04,radius);
		color=mix(vec3(0.085,0.055,0.031),vec3(0.22,0.155,0.085),n);
	}
	ALBEDO=color;
	EMISSION=color*energy;
	ALPHA=clamp(mask*tint.a*opacity,0.0,1.0);
}
