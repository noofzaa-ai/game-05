shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform vec4 flame_color : source_color = vec4(1.0, 0.24, 0.012, 1.0);
uniform sampler2D source_texture : source_color, filter_linear_mipmap;
uniform bool textured = false;
uniform float cast_clock = 0.0;
uniform float energy = 2.3;
uniform float core = 0.0;
uniform float opacity = 0.7;
uniform float fade = 1.0;
varying vec3 flame_position;
float hash(vec3 p) { return fract(sin(dot(p, vec3(127.1,311.7,74.7))) * 43758.5453); }
float noise(vec3 p) {
 vec3 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
 return mix(mix(mix(hash(i),hash(i+vec3(1,0,0)),f.x),mix(hash(i+vec3(0,1,0)),hash(i+vec3(1,1,0)),f.x),f.y),
 mix(mix(hash(i+vec3(0,0,1)),hash(i+vec3(1,0,1)),f.x),mix(hash(i+vec3(0,1,1)),hash(i+vec3(1,1,1)),f.x),f.y),f.z);
}
void vertex() { flame_position = VERTEX; }
void fragment() {
 vec3 flow = flame_position*vec3(5.0,8.0,5.0)+vec3(0.0,-cast_clock*5.0,-cast_clock*2.0);
 float n=noise(flow)*0.7+noise(flow*2.1)*0.3;
 float strands=smoothstep(0.16,0.65,n);
 vec4 tex=vec4(1.0); if(textured) tex=texture(source_texture,UV);
 float facing=abs(dot(normalize(NORMAL),normalize(VIEW)));
 float soft= mix(0.35,1.0,smoothstep(0.0,0.55,facing));
 vec3 warm=mix(flame_color.rgb,vec3(1.0,0.66,0.075),smoothstep(0.4,0.88,n)*0.7);
 vec3 heat=mix(warm,vec3(1.0,0.91,0.57),core*strands);
 ALBEDO=vec3(0.0);
 EMISSION=heat*energy*(0.5+strands*0.7)*tex.rgb;
 ALPHA=tex.a*flame_color.a*opacity*soft*mix(0.25,1.0,strands)*fade;
}
