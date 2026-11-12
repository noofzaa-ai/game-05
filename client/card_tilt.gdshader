shader_type canvas_item;
// Hub card perspective tilt for plain layers (labels, panels, the character, the backdrop). See card_tilt.gdshaderinc.
// No fragment(): text (MSDF) and style boxes draw exactly as without the material.
#include "res://client/card_tilt.gdshaderinc"

void vertex() {
	VERTEX = card_warp(card_point(VERTEX, MODEL_MATRIX), MODEL_MATRIX);
}
