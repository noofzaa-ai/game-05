shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform sampler2D flame_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform float cast_clock = 0.0;
uniform float strength = 0.0;
void fragment() {
 float u=UV.x, v=UV.y;
 float tips=pow(sin(clamp(u,0.0,1.0)*3.14159),0.65);
 vec4 fire=texture(flame_texture,vec2(u,1.0-v));
 float edge=exp(-pow((v-0.90)*46.0,2.0));
 float flow=0.65+0.35*sin(u*67.0-v*11.0-cast_clock*23.0);
 float body=fire.a*max(fire.r,max(fire.g,fire.b))*flow;
 float alpha=(body*0.65+edge)*tips*strength;
 EMISSION=(vec3(1.0,0.17,0.009)*body*1.6+vec3(1.0,0.77,0.23)*edge*2.4)*tips*strength;
 ALBEDO=vec3(0.0);
 ALPHA=clamp(alpha,0.0,0.85);
}
