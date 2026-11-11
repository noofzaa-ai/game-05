shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;

uniform sampler2D spray_texture : source_color, filter_linear_mipmap;
uniform bool use_texture = true;
uniform vec4 tint : source_color = vec4(0.57,0.89,1.0,0.32);
uniform float cast_time = 0.0;
uniform float impact_time = 1.12;
uniform float opacity = 1.0;

void fragment() {
	vec4 spray=texture(spray_texture,UV);
	float radial=length(UV-vec2(0.5))*2.0;
	float feather=1.0-smoothstep(0.28,1.0,radial);
	float soft_disk=pow(max(0.0,1.0-radial*radial),2.2);
	float shape=soft_disk*tint.a;
	if (use_texture) shape=mix(shape,spray.a,0.16);
	// Broad soft spray and small bright droplets are separate authored meshes.
	// Mist stays pale blue and translucent, without the hot/ash smoke palette.
	ALBEDO=mix(vec3(0.28,0.69,0.88),vec3(0.80,0.97,1.0),feather);
	EMISSION=ALBEDO*0.10;
	ALPHA=shape*opacity*feather*0.40;
}
