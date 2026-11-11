shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
uniform bool is_eye = false;
uniform bool is_double = false;
uniform bool is_seam = false;
uniform float cast_time = 0.0;
varying vec3 shape_position;
void vertex(){ shape_position = VERTEX; }
void fragment(){
    float rim = pow(1.0-clamp(dot(normalize(NORMAL),normalize(VIEW)),0.0,1.0),2.5);
    float pulse = .94+.06*sin(cast_time*4.0+shape_position.y*7.0);
    vec3 ink = is_double ? vec3(.009,.003,.020) : vec3(.026,.013,.048);
    ALBEDO = is_eye ? vec3(.50,.42,1.0) : is_seam ? vec3(.10,.055,.24) : ink + vec3(.025,.006,.050)*rim;
    EMISSION = is_eye ? vec3(.62,.52,1.0)*3.0 : is_seam ? vec3(.20,.095,.47)*.65 : vec3(.23,.055,.53)*rim*pulse*1.1;
    ROUGHNESS = .91; SPECULAR = .08;
}
