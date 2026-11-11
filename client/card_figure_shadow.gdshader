shader_type canvas_item;
// Soft dark shadow of the class card character: the portrait's own transparent render, alpha blurred with
// 9 taps and painted one flat colour. Drawn on the backdrop, under the character (client/card_portrait.gd).
// Author: ui-programmer. Target: Compatibility renderer (web). Budget: one small quad per card, 9 reads,
// single pass (a two-pass blur would need another viewport; at ~150x200 px a single 9-tap pass is cheaper).
// Only the active card's portrait updates per frame, so the shadow costs nothing on the other cards.

group_uniforms look;
uniform vec4 shadow_color : source_color = vec4(0.0, 0.0, 0.0, 0.6);
uniform float blur : hint_range(0.0, 8.0) = 2.5; // tap distance in texture pixels
group_uniforms;

void fragment() {
	vec2 px = TEXTURE_PIXEL_SIZE * blur;
	float a = texture(TEXTURE, UV).a * 0.2;
	a += texture(TEXTURE, UV + vec2(px.x, 0.0)).a * 0.12;
	a += texture(TEXTURE, UV - vec2(px.x, 0.0)).a * 0.12;
	a += texture(TEXTURE, UV + vec2(0.0, px.y)).a * 0.12;
	a += texture(TEXTURE, UV - vec2(0.0, px.y)).a * 0.12;
	a += texture(TEXTURE, UV + px * 1.4).a * 0.08;
	a += texture(TEXTURE, UV - px * 1.4).a * 0.08;
	a += texture(TEXTURE, UV + vec2(px.x, -px.y) * 1.4).a * 0.08;
	a += texture(TEXTURE, UV + vec2(-px.x, px.y) * 1.4).a * 0.08;
	COLOR = vec4(shadow_color.rgb, shadow_color.a * a);
}
