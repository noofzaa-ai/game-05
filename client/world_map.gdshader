shader_type canvas_item;
uniform float saturation=0.62;
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1)),f.x),f.y);}
void fragment(){
 vec4 base=texture(TEXTURE,UV);
 float gray=dot(base.rgb,vec3(.2126,.7152,.0722));base.rgb=mix(vec3(gray),base.rgb,saturation)*.87;
 float n=noise(UV*18.0)*.6+noise(UV*43.0)*.3+noise(UV*91.0)*.1;
 float goblin=length((UV-vec2(.18,.64))/vec2(.19,.20));
 float home=length((UV-vec2(.105,.15))/vec2(.125,.15));
 float reveal=1.0-smoothstep(.83+n*.13,1.07+n*.13,min(goblin,home));
 vec3 fog=mix(vec3(.115,.17,.225),vec3(.39,.46,.53),n);
 vec3 hidden=mix(base.rgb*.25,fog,.92);
 COLOR=vec4(mix(hidden,base.rgb,reveal),base.a);
}
