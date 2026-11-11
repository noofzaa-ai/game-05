shader_type spatial;
render_mode unshaded,cull_disabled,depth_draw_never,blend_add;
uniform float cast_time = 0.0;
uniform float visibility_factor = 0.0;
uniform float kind = 0.0;
void fragment(){
    vec2 q = (UV-.5)*2.0;
    float sway = .14*sin(q.y*5.0-cast_time*16.0);
    float mask = (1.0-smoothstep(.15,.85,abs(q.x+sway)))*(1.0-smoothstep(.30,1.0,abs(q.y)));
    ALBEDO = vec3(.45,.08,1.0);
    EMISSION = vec3(.55,.12,1.0)*2.3;
    ALPHA = mask*visibility_factor;
}
