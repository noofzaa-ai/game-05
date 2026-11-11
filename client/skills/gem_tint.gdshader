shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;
uniform sampler2D sprite_texture : source_color, filter_linear;
uniform bool has_texture = false;
uniform vec4 energy_color : source_color = vec4(1.0);
uniform float source_alpha = 1.0;
void fragment(){vec4 sprite=has_texture?texture(sprite_texture,UV):vec4(1.0);float brightness=max(sprite.r,max(sprite.g,sprite.b));ALBEDO=energy_color.rgb*brightness;ALPHA=sprite.a*source_alpha*energy_color.a;}
