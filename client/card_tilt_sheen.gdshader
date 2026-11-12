shader_type canvas_item;
// Hub card perspective tilt + leather/parchment sheen for the frame art (card_frame_<class>.png). A soft warm band
// sweeps across the frame as the card turns, and the outer edge facing the pointer catches a thin highlight.
// Author: ui-programmer. Target: Compatibility renderer. Cost: one texture read (the frame itself) and a few
// maths ops per frame pixel; no extra texture. Only frame pixels light up (multiplied by the art's alpha).
#include "res://client/card_tilt.gdshaderinc"

group_uniforms sheen;
uniform vec4 sheen_color : source_color = vec4(1.0, 0.86, 0.62, 1.0);
uniform float sheen_strength = 0.0;   // 0 = off (idle card)
uniform float sheen_width = 0.16;     // band half-width, card uv
uniform float edge_strength = 0.0;
uniform float edge_width = 0.035;     // card uv
group_uniforms;

varying vec2 card_uv;

void vertex() {
	vec2 p = card_point(VERTEX, MODEL_MATRIX);
	card_uv = p / card_size;
	VERTEX = card_warp(p, MODEL_MATRIX);
}

void fragment() {
	vec4 c = COLOR; // (already the texture times the modulate)
	vec2 uv = card_uv;
	// diagonal band; it slides across the card with the tilt
	float s = dot(uv - 0.5, normalize(vec2(1.0, 0.65)));
	float centre = -(tilt.x * 0.55 + tilt.y * 0.35);
	float band = exp(-pow((s - centre) / sheen_width, 2.0));
	// thin rim light on the outer edge nearest the pointer
	float edge_d = min(min(uv.x, 1.0 - uv.x) * card_size.x, min(uv.y, 1.0 - uv.y) * card_size.y) / card_size.x;
	float rim = 1.0 - smoothstep(0.0, edge_width, edge_d);
	vec2 dir = uv - 0.5;
	float facing = length(tilt) > 0.001 ? clamp(dot(normalize(dir), normalize(tilt)) * 0.8 + 0.2, 0.0, 1.0) : 0.0;
	float light = band * sheen_strength + rim * facing * edge_strength * min(length(tilt), 1.0);
	// brighter on the light parchment, softer on dark leather (keeps it a sheen, not a white wash)
	float luma = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	c.rgb += sheen_color.rgb * light * (0.35 + 0.65 * luma) * c.a;
	COLOR = c;
}
