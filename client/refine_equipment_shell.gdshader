shader_type spatial;
render_mode cull_front, unshaded, blend_add, depth_draw_never, shadows_disabled;
uniform vec4 aura : source_color;
uniform float pixels = 2.0;
uniform float intensity = 0.25;
void vertex() {
 vec3 direction = normalize(NORMAL);
 float units_to_view = max(length(mat3(MODELVIEW_MATRIX) * direction), 0.000001);
 float depth = max(-(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z, 0.0001);
 float pixel_size = 2.0 / (abs(PROJECTION_MATRIX[1][1]) * max(VIEWPORT_SIZE.y, 1.0));
 if (PROJECTION_MATRIX[3][3] < 0.5) { pixel_size *= depth; }
 VERTEX += direction * pixels * pixel_size / units_to_view;
}
void fragment() {
 ALBEDO = aura.rgb;
 EMISSION = aura.rgb * intensity * 2.0;
 ALPHA = intensity * 0.65;
}
