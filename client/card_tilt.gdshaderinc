// Shared vertex warp of a hub class card (client/card_deck_screen.gd HubCard): every layer of the card (frame,
// window, backdrop, character, labels) uses it with the same card uniforms, so the whole card turns as one
// rigid sheet in perspective toward the pointer (the depth parallax is done by moving the layers themselves).
// Author: ui-programmer. Target: Compatibility renderer (web/mobile). Cost: a few vertex ops per quad, no
// extra pass or viewport. With tilt = 0 the warp is the identity; idle cards have no material at all.

group_uniforms card;
uniform vec2 card_size = vec2(300.0, 450.0);   // card px (local)
uniform vec2 card_x = vec2(1.0, 0.0);          // card -> canvas transform (Control.get_global_transform())
uniform vec2 card_y = vec2(0.0, 1.0);
uniform vec2 card_o = vec2(0.0);
group_uniforms;

group_uniforms motion;
uniform vec2 tilt = vec2(0.0);                 // smoothed pointer offset from the card centre, -1..1
uniform vec2 max_angle = vec2(0.12, 0.09);     // radians: yaw (x), pitch (y) at full tilt
uniform float focal = 1000.0;                  // perspective distance, card px
group_uniforms;

// The vertex in card px (0..card_size), from the item's own vertex.
vec2 card_point(vec2 vertex, mat4 model) {
	vec2 world = mat2(model[0].xy, model[1].xy) * vertex + model[3].xy;
	return inverse(mat2(card_x, card_y)) * (world - card_o);
}

// The item's vertex that shows card point `p` turned toward the pointer in perspective.
vec2 card_warp(vec2 p, mat4 model) {
	vec2 d = p - card_size * 0.5;
	float yaw = tilt.x * max_angle.x;
	float pitch = tilt.y * max_angle.y;
	// the side under the pointer goes away from the viewer (the card faces the pointer)
	float z = -d.x * sin(yaw) - d.y * sin(pitch);
	vec2 flat_d = vec2(d.x * cos(yaw), d.y * cos(pitch));
	vec2 q = flat_d * (focal / max(focal - z, 1.0)) + card_size * 0.5;
	vec2 world = mat2(card_x, card_y) * q + card_o;
	mat2 model_basis = mat2(model[0].xy, model[1].xy);
	return inverse(model_basis) * (world - model[3].xy);
}
