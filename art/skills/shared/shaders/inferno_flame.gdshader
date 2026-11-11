shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform sampler2D flame_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform float cast_clock = 0.0;
uniform float opacity = 1.0;
uniform float heat = 1.0;
uniform float variant = 0.0;
void fragment() {
 vec2 uv=UV;
 // The painted silhouette defines the flame, with a small flowing UV warp.
 float warp=sin(uv.y*13.0-cast_clock*8.0+variant)*sin(uv.x*17.0+cast_clock*3.0)*0.012;
 uv.x+=warp*smoothstep(0.15,0.85,uv.y);
 vec4 flame=texture(flame_texture,clamp(uv,vec2(0.0),vec2(1.0)));
 float brightness=max(flame.r,max(flame.g,flame.b));
 float core=smoothstep(0.6,1.0,flame.g)*smoothstep(0.3,0.85,flame.b);
 ALBEDO=flame.rgb;
 EMISSION=flame.rgb*(0.4+core*1.4)*heat;
 ALPHA=flame.a*opacity*smoothstep(0.015,0.1,brightness);
}
