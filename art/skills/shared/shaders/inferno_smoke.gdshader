shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
void vertex() {
 vec3 model_scale=vec3(length(MODEL_MATRIX[0].xyz),length(MODEL_MATRIX[1].xyz),length(MODEL_MATRIX[2].xyz));
 MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0]*model_scale.x, INV_VIEW_MATRIX[1]*model_scale.y, INV_VIEW_MATRIX[2]*model_scale.z, MODEL_MATRIX[3]);
}
void fragment() {
 vec2 p=UV*2.0-1.0;
 float shape=exp(-dot(p,p)*3.5)*(1.0-smoothstep(0.65,1.0,length(p)));
 ALBEDO=COLOR.rgb; ALPHA=COLOR.a*shape*0.14;
}
