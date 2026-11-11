shader_type spatial;
// The warning circle of a ground area (a mage's hex): a sharp rim with ink ticks that spin, and a
// fill that grows from the center to the rim as the detonation comes (progress 0 -> 1). Near the end
// the rim pulses faster. Flat quad on the ground, one shader for every area (compiled at stage load).
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled, blend_mix;

uniform vec4 color : source_color = vec4(0.75, 0.35, 1.0, 1.0);
uniform vec4 ink_color : source_color = vec4(0.06, 0.04, 0.09, 1.0);
uniform float progress = 0.0;
uniform float time = 0.0;
uniform float opacity = 1.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float t = clamp(progress, 0.0, 1.0);
	// The rim: dark ink under a bright line, so it reads on light and dark ground alike.
	float rim = smoothstep(0.06, 0.0, abs(r - 0.93));
	float rim_ink = smoothstep(0.12, 0.03, abs(r - 0.93));
	// Ticks around the rim, turning slowly (a rune ring).
	float ticks = step(0.55, fract((a / 6.2831853) * 16.0 + time * 0.25)) * smoothstep(0.1, 0.02, abs(r - 0.82));
	// The fill reaches the rim at detonation; its edge is bright.
	float edge = mix(0.05, 0.93, t * t * (3.0 - 2.0 * t));
	float fill = smoothstep(edge + 0.02, edge - 0.02, r) * (0.22 + 0.25 * t);
	float front = smoothstep(0.05, 0.0, abs(r - edge)) * 0.9;
	float pulse = 0.75 + 0.25 * sin(time * mix(6.0, 22.0, t));
	vec3 rgb = mix(ink_color.rgb, color.rgb, clamp(rim + ticks + front + fill * 2.0, 0.0, 1.0));
	float alpha = max(max(rim * pulse, rim_ink * 0.85), max(ticks * 0.8, max(front, fill)));
	ALBEDO = rgb;
	ALPHA = alpha * step(r, 1.0) * opacity * color.a;
}
