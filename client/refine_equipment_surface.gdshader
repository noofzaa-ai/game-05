shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, shadows_disabled;
uniform vec4 aura : source_color;
uniform float intensity = 0.2;
void fragment() {
 float rim = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 2.0);
 ALBEDO = aura.rgb * intensity * (0.12 + rim * 0.88);
 ALPHA = 0.55;
}
