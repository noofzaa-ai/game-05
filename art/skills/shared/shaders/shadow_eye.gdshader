shader_type spatial;
render_mode unshaded;
uniform float strength = 0.0;
void fragment(){
    ALBEDO = vec3(1.0,.98,1.0);
    EMISSION = vec3(1.0,.92,1.0)*(1.0+7.0*strength);
    ROUGHNESS = 1.0;
}
