shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;

uniform sampler2D dust_texture : source_color, filter_linear_mipmap;
uniform bool use_texture = false;
uniform vec4 tint : source_color = vec4(0.69,0.51,0.32,0.58);
uniform float cast_time = 0.0;
uniform float impact_time = 1.12;
uniform float opacity = 1.0;
varying vec3 cloud_position;

void vertex() { cloud_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p) {
	vec2 i=floor(p),f=fract(p),u=f*f*(3.0-2.0*f);
	return mix(mix(hash(i),hash(i+vec2(1.0,0.0)),u.x),mix(hash(i+vec2(0.0,1.0)),hash(i+vec2(1.0,1.0)),u.x),u.y);
}
void fragment() {
	float age=max(0.0,cast_time-impact_time);
	vec2 drift=vec2(age*0.17,-age*0.12);
	float curl=noise(UV*5.5+drift+cloud_position.xz*0.18);
	float detail=noise(UV*11.0-drift);
	float shape=1.0;
	if (use_texture) {
		float radial=length(UV-vec2(0.5))*2.0;
		shape=texture(dust_texture,UV).a;
		shape*=1.0-smoothstep(0.18,1.0,radial+(0.5-curl)*0.12);
	} else {
		if (!FRONT_FACING) discard;
		float facing=abs(dot(normalize(NORMAL),normalize(VIEW)));
		shape=pow(smoothstep(0.02,0.70,facing+(curl-0.5)*0.18),1.7)*tint.a;
	}
	float breakup=smoothstep(1.18,2.24,age);
	float erosion=smoothstep(mix(0.05,0.68,breakup)-0.16,mix(0.05,0.68,breakup)+0.16,curl);
	vec3 color=mix(vec3(0.24,0.16,0.095),vec3(0.76,0.59,0.37),0.34+0.55*curl);
	ALBEDO=color*(0.92+0.08*detail);
	EMISSION=vec3(0.0);
	ALPHA=clamp(shape*opacity*erosion*(use_texture ? 0.65 : 0.18),0.0,0.75);
}
