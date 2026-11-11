shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform float phase = 0.0;
uniform float strength = 0.0;
uniform float shock = 0.0;
void fragment() {
 vec2 p=(UV-0.5)*2.0;
 float r=length(p), angle=atan(p.y,p.x);
 float radius=mix(0.76,mix(0.08,0.90,phase),shock);
 float ring=exp(-pow((r-radius)*40.0,2.0));
 float inner=exp(-pow((r-radius*0.79)*65.0,2.0))*0.5;
 float runes=pow(max(0.0,sin(angle*12.0+phase*3.0)),16.0)*exp(-pow((r-radius*0.9)*40.0,2.0));
 float breaks=mix(0.35,1.0,smoothstep(-0.4,0.7,sin(angle*7.0-phase*4.0)));
 float intensity=(ring+inner+runes)*breaks*strength;
 EMISSION=vec3(1.0,0.5,0.035)*intensity*3.8;
 ALBEDO=vec3(0.0); ALPHA=clamp(intensity,0.0,0.9);
}
