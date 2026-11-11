shader_type spatial;
render_mode unshaded,cull_disabled,depth_draw_never;
uniform float cast_time = 0.0;
uniform float visibility_factor = 1.0;
uniform float flake_tint = 1.0;
uniform float kind = 0.0; // 0 dark flame, 1 billowing smoke, 2 tiny embers
varying vec3 shape_position;
float hash(vec3 p){return fract(sin(dot(p,vec3(127.1,311.7,74.7)))*43758.5453);}
float noise(vec3 p){
    vec3 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);
    return mix(mix(mix(hash(i),hash(i+vec3(1,0,0)),f.x),mix(hash(i+vec3(0,1,0)),hash(i+vec3(1,1,0)),f.x),f.y),mix(mix(hash(i+vec3(0,0,1)),hash(i+vec3(1,0,1)),f.x),mix(hash(i+vec3(0,1,1)),hash(i+vec3(1,1,1)),f.x),f.y),f.z);
}
void vertex(){
    shape_position=VERTEX;
    float rise=smoothstep(0.0,.7,cast_time);
    if(kind<1.5){
        VERTEX.x+=sign(VERTEX.x)*(.06+.05*sin(cast_time*1.3+VERTEX.z*3.0))*rise;
        VERTEX.y+=sin(VERTEX.x*3.0+cast_time*1.8)*.04;
    }else{VERTEX.y+=.04*sin(cast_time*2.0+VERTEX.x*8.0);}
}
void fragment(){
    vec3 p=shape_position*vec3(3.2,2.5,2.4)+vec3(0,-cast_time*.85,0);
    float n=noise(p),fine=noise(p*2.3+vec3(0,-cast_time*.8,0));
    if(kind>1.5){ALBEDO=mix(vec3(.004,.002,.009),vec3(.27,.095,.60),flake_tint);EMISSION=ALBEDO*1.35*flake_tint;ALPHA=.55+.30*n;}
    else{
        vec2 q=(UV-.5)*2.0;
        float warp=noise(vec3(UV*4.0,cast_time*.4)+shape_position*.7)-.5;
        float horizontal=abs(q.x+warp*.42);
        float billow=.68+.12*sin(q.y*7.0+cast_time*1.6+shape_position.x*2.0)+warp*.12;
        float envelope=(1.0-smoothstep(billow-.20,billow+.24,horizontal))*(1.0-smoothstep(.61,.99,abs(q.y)));
        float turbulence=smoothstep(.20,.72,n*.78+fine*.27);
        float light=smoothstep(.42,.77,n+.15*fine);
        if(kind>.5){
            float cloud=envelope*turbulence;
            ALBEDO=mix(vec3(.005,.003,.012),vec3(.075,.037,.14),light*.65);
            EMISSION=vec3(.075,.029,.18)*light*cloud*.48;
            ALPHA=cloud*.56;
        }else{
            float tip=.58+.15*sin(q.x*7.0+cast_time*2.2)+warp*.26;
            float tongues=1.0-smoothstep(tip,tip+.27,q.y);
            float fire=envelope*tongues*turbulence;
            ALBEDO=mix(vec3(.007,.003,.018),vec3(.24,.075,.47),light);
            EMISSION=mix(vec3(.025,.007,.065),vec3(.34,.105,.73),light)*.85;
            ALPHA=fire*.64;
        }
    }
    ALPHA *= visibility_factor;
}
