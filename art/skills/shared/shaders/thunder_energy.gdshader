shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

uniform vec4 tint : source_color = vec4(0.06,0.38,1.0,1.0);
uniform float cast_time = 0.0;
uniform float impact_time = 1.12;
uniform float opacity = 1.0;
uniform float energy = 1.6;
uniform float surface_kind = 0.0; // halo0, core1, ring2, spark3, flash4, haze5, shockwave6, ground spark7
varying vec3 cast_position;

void vertex() { cast_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p) {
	vec2 i=floor(p),f=fract(p),u=f*f*(3.0-2.0*f);
	return mix(mix(hash(i),hash(i+vec2(1.0,0.0)),u.x),mix(hash(i+vec2(0.0,1.0)),hash(i+vec2(1.0,1.0)),u.x),u.y);
}
void fragment() {
	float age=max(0.0,cast_time-impact_time);
	float cell=noise(cast_position.xz*2.7+vec2(0.0,cast_position.y*0.41));
	float pulse=0.78+0.22*sin(age*24.0+cell*6.283);
	float mask=1.0;
	vec3 color=tint.rgb;
	if (surface_kind < 2.5) {
		float across=abs(UV.y-0.5)*2.0;
		mask=pow(max(0.0,1.0-across),surface_kind<0.5 ? 0.8 : 0.35);
		float segment=noise(vec2(UV.x*31.0,age*5.0+cell*9.0));
		mask*=mix(0.43,1.0,smoothstep(0.10,0.55,segment));
		if (surface_kind<0.5) color=mix(vec3(0.035,0.10,0.90),vec3(0.04,0.50,1.0),cell);
		else if (surface_kind<1.5) color=mix(vec3(0.23,0.60,1.0),vec3(0.70,0.94,1.0),cell);
		else color=mix(vec3(0.08,0.25,1.0),vec3(0.28,0.76,1.0),cell);
	} else if (surface_kind>6.5) {
		float zig=sin(UV.y*15.0+cell*8.0)*0.13;
		float across=abs(UV.x-0.5-zig)*2.0;
		mask=(1.0-smoothstep(0.10,0.95,across))*(1.0-smoothstep(0.34,0.52,abs(UV.y-0.5)));
		color=mix(vec3(0.035,0.32,1.0),vec3(0.72,0.95,1.0),1.0-smoothstep(0.08,0.40,across));
		pulse=0.65+0.35*sin(age*31.0+cell*19.0);
	} else if (surface_kind>5.5) {
		float shoulder=sin(clamp(UV.y,0.0,1.0)*3.14159);
		float grain=noise(vec2(UV.x*17.0,UV.y*4.0-age*2.0));
		mask=shoulder*(0.55+0.45*grain);
		color=mix(vec3(0.025,0.04,0.65),vec3(0.06,0.41,1.0),grain);
	} else if (surface_kind>4.5) {
		float radial=length(UV-vec2(0.5))*2.0;
		mask=pow(max(0.0,1.0-radial*radial),2.2)*0.10;
		color=vec3(0.055,0.26,0.95);
	} else if (surface_kind>3.5) {
		color=vec3(0.65,0.91,1.0);
		pulse=1.0;
	} else color=mix(vec3(0.17,0.52,1.0),vec3(0.78,0.96,1.0),cell);
	float wall=(!FRONT_FACING && surface_kind<2.5) ? 0.40 : 1.0;
	ALBEDO=color*energy*pulse*mask*opacity*wall;
	EMISSION=vec3(0.0);
	ALPHA=clamp(mask*opacity*tint.a*wall,0.0,1.0);
}
