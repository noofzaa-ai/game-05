shader_type canvas_item;
// Hub card perspective tilt for the window content (backdrop, its light, the 3D character render) while the card
// is tilted: the clip_children mask cannot take a material, so this clips to the rounded window itself, in card px
// before the warp (so the clip turns with the card). Cost: one rounded-rect distance per pixel.
#include "res://client/card_tilt.gdshaderinc"

uniform vec4 clip_rect = vec4(0.0, 0.0, 300.0, 450.0); // window x, y, w, h in card px
uniform float clip_radius = 20.0;

varying vec2 card_p;

void vertex() {
	card_p = card_point(VERTEX, MODEL_MATRIX);
	VERTEX = card_warp(card_p, MODEL_MATRIX);
}

void fragment() {
	vec2 half_size = clip_rect.zw * 0.5;
	vec2 q = abs(card_p - clip_rect.xy - half_size) - half_size + clip_radius;
	float dist = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - clip_radius;
	vec4 c = COLOR; // (already the texture times the modulate)
	c.a *= clamp(0.5 - dist, 0.0, 1.0);
	COLOR = c;
}
