shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;
uniform vec4 energy_color : source_color = vec4(0.9,0.15,0.3,1.0);
uniform float effect_time = 0.0;
uniform float rim_strength = 0.30;  // frost armor uses a stronger rim: its pale blue vanished on the sand
varying vec3 local_point;
void vertex(){local_point=VERTEX;}
void fragment(){
 float rim=pow(1.0-abs(dot(normalize(NORMAL),normalize(VIEW))),2.2);
 float pulse=pow(max(0.0,sin(local_point.y*18.0-effect_time*5.0+sin(local_point.x*9.0)*0.5)),12.0);
 ALBEDO=energy_color.rgb;
 ALPHA=0.025+rim*rim_strength+pulse*0.045;
}
