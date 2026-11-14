shader_type spatial;
// Ink-wash version of a daiyooo VFX flipbook sprite (art/vfx/class_skills, art/vfx/status; Boss 2026-11-15).
// Replaces the imported StandardMaterial3D (unshaded, alpha + depth pre-pass, texture x colour) at load time by
// client/vfx/ink_vfx.gd, so the GLBs stay untouched. Same quad, same draw: one texture read plus vfx_ink()
// (ink edge, wash glazes, 3 tones, grain). Mix blending, no depth write (the pre-pass of the original is dropped).
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled, blend_mix;

#include "res://client/vfx/vfx_common.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 tint : source_color = vec4(1.0);
uniform vec3 uv_scale = vec3(1.0);
uniform vec3 uv_offset = vec3(0.0);
uniform vec4 ink_color : source_color = vec4(0.10, 0.08, 0.07, 1.0);
uniform float grain_seed = 0.0;
uniform float grain_scale = 9.0;  // grain cells across the sprite
uniform bool billboard = false;  // turn the quad to the camera (projectile glows; daiyooo meshes are placed by their clip)

void vertex() {
	if (billboard) {
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
		MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	}
}

void fragment() {
	vec2 uv = UV * uv_scale.xy + uv_offset.xy;
	vec4 t = texture(albedo_tex, uv) * tint;
	vec4 o = vfx_ink(t.rgb, t.a, UV, UV * grain_scale + grain_seed, ink_color.rgb);
	if (o.a <= 0.004) {
		discard;
	}
	ALBEDO = o.rgb;
	ALPHA = o.a;
}
