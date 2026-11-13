shader_type spatial;
// Draw-style prototype B/C (tech-artist 2026-11-13): one full-screen pass that turns the rendered 3D frame
// into an ink-and-wash illustration. Drawn on a quad parked just in front of the camera (client/draw_style/
// draw_style.gd), as the first transparent draw, so world VFX, health bars and numbers drawn after it stay
// clean. Target: GL Compatibility (WebGL2). Uses the screen and depth textures (both work in Compatibility:
// Godot copies them once after the opaque pass). Cost: 5 depth + 3 colour samples and some ALU noise per pixel.
// - ink lines where the depth jumps (silhouettes) or bends (creases), width varied by world-anchored noise;
// - the colour posterized into flat value bands (keeping its hue);
// - pen hatching in the dark bands, anchored to world position so it does not swim;
// - paper grain and a watercolour wash, slight desaturation and warmth.
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;  // no mipmap hint: a mipmapped screen copy is rebuilt every frame (cost check: docs/tech/draw_style.md)
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

group_uniforms ink;
uniform vec4 ink_color : source_color = vec4(0.10, 0.08, 0.07, 1.0);
uniform float line_pixels = 1.4;      // sample distance for the edge test, in pixels (line thickness)
uniform float silhouette = 0.06;      // relative depth jump that makes a line (smaller = more lines)
uniform float crease = 0.012;         // relative depth bend (second derivative) that makes a line
uniform float colour_edge = 0.0;      // >0 also inks strong colour edges (texture detail): off by default
uniform float line_strength = 0.9;
uniform float far_fade = 60.0;        // metres where lines fade out (the horizon/sky gets none)
group_uniforms;

group_uniforms tone;
uniform float bands = 3.0;            // value bands (2-4)
uniform float band_mix = 0.65;        // 0 = smooth original lighting, 1 = fully flat bands
uniform float saturation = 0.8;
uniform vec3 warmth = vec3(1.04, 1.0, 0.9);
group_uniforms;

group_uniforms paper;
uniform float hatch_strength = 0.35;
uniform float hatch_density = 6.0;    // strokes per metre (world)
uniform float hatch_below = 0.32;     // value under which hatching starts
uniform float grain_strength = 0.09;
uniform float wash_strength = 0.07;
uniform vec3 paper_tint = vec3(0.96, 0.92, 0.84);
uniform float paper_mix = 0.08;       // how much the paper colour shows through everything
group_uniforms;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

// View-space position of the pixel at `uv` (Compatibility: depth is 0..1 OpenGL style).
vec3 view_position(vec2 uv, mat4 inv_projection) {
	float depth = texture(depth_tex, uv).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(uv * 2.0 - 1.0, depth * 2.0 - 1.0);
#else
	vec3 ndc = vec3(uv * 2.0 - 1.0, depth);
#endif
	vec4 view = inv_projection * vec4(ndc, 1.0);
	return view.xyz / view.w;
}

void vertex() {
	// (Placed and sized by draw_style.gd to cover the view; nothing to do here.)
}

void fragment() {
	vec2 px = 1.0 / VIEWPORT_SIZE;
	vec3 centre_view = view_position(SCREEN_UV, INV_PROJECTION_MATRIX);
	float d = -centre_view.z;
	vec3 world = (INV_VIEW_MATRIX * vec4(centre_view, 1.0)).xyz;

	// Line width wobbles along the world (thicker and thinner strokes like a brush).
	float wobble = value_noise(world.xz * 1.6 + world.y * 0.8);
	vec2 o = px * line_pixels * (0.6 + 0.9 * wobble);
	float dl = -view_position(SCREEN_UV - vec2(o.x, 0.0), INV_PROJECTION_MATRIX).z;
	float dr = -view_position(SCREEN_UV + vec2(o.x, 0.0), INV_PROJECTION_MATRIX).z;
	float dd = -view_position(SCREEN_UV - vec2(0.0, o.y), INV_PROJECTION_MATRIX).z;
	float du = -view_position(SCREEN_UV + vec2(0.0, o.y), INV_PROJECTION_MATRIX).z;
	// silhouette: the largest jump to a neighbour, relative to distance (a far wall vs a near goblin)
	float jump = max(max(abs(dl - d), abs(dr - d)), max(abs(dd - d), abs(du - d))) / max(d, 0.01);
	// crease: the depth slope changes (a box corner, a roof ridge) even without a jump
	float bend = (abs(dl + dr - 2.0 * d) + abs(dd + du - 2.0 * d)) / max(d, 0.01);
	float line = max(smoothstep(silhouette, silhouette * 2.0, jump), smoothstep(crease, crease * 2.0, bend));

	vec3 colour = texture(screen_tex, SCREEN_UV).rgb;
	if (colour_edge > 0.0) {
		vec3 cl = texture(screen_tex, SCREEN_UV - vec2(o.x, 0.0)).rgb;
		vec3 cu = texture(screen_tex, SCREEN_UV + vec2(0.0, o.y)).rgb;
		float edge = length(colour - cl) + length(colour - cu);
		line = max(line, smoothstep(colour_edge, colour_edge * 2.0, edge));
	}
	line *= 1.0 - smoothstep(far_fade * 0.6, far_fade, d);
	// ink gaps: a dry brush does not lay a perfectly unbroken line
	line *= 0.75 + 0.25 * smoothstep(0.2, 0.6, value_noise(SCREEN_UV * VIEWPORT_SIZE * 0.12));

	// Flat value bands: quantize the brightness, keep the hue.
	float value = max(max(colour.r, colour.g), colour.b);
	float stepped = (floor(value * bands + 0.5) / bands);
	stepped = mix(value, max(stepped, 0.04), band_mix);
	colour *= stepped / max(value, 0.001);

	// Pen hatching in the dark: strokes fixed to the world so they stay put while the camera moves.
	vec2 plane = world.xz + vec2(world.y * 0.7, -world.y * 0.7);
	float wiggle = value_noise(plane * 1.5) * 0.6;
	float s = abs(fract((plane.x + plane.y) * hatch_density + wiggle) - 0.5);
	float stroke = (1.0 - smoothstep(0.07, 0.15, s)) * (1.0 - smoothstep(hatch_below * 0.5, hatch_below, value));
	stroke *= smoothstep(0.25, 0.55, value_noise(plane * vec2(8.0, 2.0)));
	stroke *= 1.0 - smoothstep(far_fade * 0.5, far_fade, d);
	colour *= 1.0 - stroke * hatch_strength;

	// Paper: a fixed grain on the screen (the paper does not move), a soft wash, and its warm tint.
	vec2 screen_px = SCREEN_UV * VIEWPORT_SIZE;
	float grain = value_noise(screen_px * 0.45) * 0.6 + hash(floor(screen_px)) * 0.4;
	float wash = value_noise(screen_px * 0.006) * 0.7 + value_noise(screen_px * 0.02) * 0.3;
	colour *= 1.0 - grain_strength * (grain - 0.3);
	colour *= 1.0 - wash_strength * (wash - 0.4);
	float luma = dot(colour, vec3(0.299, 0.587, 0.114));
	colour = mix(vec3(luma), colour, saturation) * warmth;
	colour = mix(colour, colour * paper_tint + paper_tint * 0.05, paper_mix);

	ALBEDO = mix(colour, ink_color.rgb, line * line_strength);
}
