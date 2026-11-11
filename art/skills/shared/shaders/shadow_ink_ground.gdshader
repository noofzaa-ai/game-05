shader_type spatial;
render_mode unshaded,cull_disabled,depth_draw_never;
uniform float cast_time = 0.0;
varying vec3 shape_position;
void vertex(){shape_position=VERTEX;}
void fragment(){
    vec2 q=(UV-.5)*2.0;
    float swirl=.5+.5*sin(shape_position.x*6.0+sin(shape_position.z*8.0)+cast_time*.7);
    float mask=(1.0-smoothstep(.30,.99,length(q+vec2(.12*sin(q.y*5.0),0.0))));
    ALBEDO=vec3(.010,.005,.024);EMISSION=vec3(.025,.009,.059)*swirl*.5;
    ALPHA=mask*(.33+.15*swirl);
}
