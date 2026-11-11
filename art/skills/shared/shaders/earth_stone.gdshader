shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform vec4 tint : source_color = vec4(0.55,0.44,0.30,1.0);
uniform float cast_time = 0.0;
uniform float impact_time = 1.12;
uniform float opacity = 1.0;
varying vec3 stone_position;

void vertex() { stone_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
float grain(vec3 p) { return fract(sin(dot(floor(p*16.0),vec3(127.1,311.7,74.7)))*43758.5453); }
void fragment() {
	float grit=grain(stone_position);
	ALBEDO=tint.rgb*(0.87+0.19*grit);
	ROUGHNESS=0.97;
	METALLIC=0.0;
	SPECULAR=0.12;
	EMISSION=tint.rgb*0.035;
	ALPHA=opacity;
}
