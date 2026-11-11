shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

// Geometry and its animation come from Blender. This shader adds the moving
// fire edge and HDR light that a GLB's static material cannot carry.
uniform vec4 tint : source_color = vec4(1.0, 0.30, 0.018, 1.0);
uniform float cast_time = 0.0;
uniform float impact_time = 1.12;
uniform float opacity = 1.0;
uniform float energy = 3.0;
uniform float surface_kind = 0.0; // flash 0, core 1, ring 2, flame 3, crack 4, spark 5, lasting star 6
varying vec3 cast_position;

void vertex() {
	cast_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float turbulence(vec2 p) {
	return noise(p) * 0.55 + noise(p * 2.03) * 0.28 + noise(p * 4.07) * 0.17;
}
void fragment() {
	float age = max(0.0, cast_time - impact_time);
	// A short white impulse is intentional. The large forms return to gold
	// and orange afterwards, leaving the ground star as the late focal point.
	float impact_peak = (1.0 - smoothstep(0.12, 0.30, age));
	float mask = 1.0;
	float heat = 0.75;
	float brightness = 1.0;
	if (surface_kind > 0.5 && surface_kind < 3.5) {
		vec2 moving_uv = UV * vec2(7.0, 2.0) + vec2(age * 0.50, -age * 1.45);
		float fire = turbulence(moving_uv);
		float tip = UV.y + fire * 0.17;
		float edge = smoothstep(0.0, 0.045, UV.y) * (1.0 - smoothstep(0.72, 1.08, tip));
		mask = edge * smoothstep(0.10, 0.28, fire + (1.0 - UV.y) * 0.28);
		heat = clamp(1.0 - UV.y * 0.85 + fire * 0.30, 0.0, 1.0);
		if (surface_kind < 1.5) {
			mask = smoothstep(0.02, 0.20, fire) * (1.0 - smoothstep(0.83, 1.0, UV.y));
			heat = clamp(0.91 - UV.y * 0.56 + fire * 0.15, 0.0, 1.0);
			brightness = mix(0.67, 1.18, impact_peak);
			// Closed eruption lobes otherwise add their hidden back walls to
			// the same pixel, washing every visible edge into white.
			if (!FRONT_FACING) brightness *= 0.20;
		} else if (surface_kind < 2.5) {
			// The rim's broad body stays filled. Only its outer lip is torn.
			mask = smoothstep(0.0, 0.055, UV.y) * (1.0 - smoothstep(0.87, 1.0, UV.y));
			mask *= mix(0.84, 1.0, smoothstep(0.15, 0.66, fire));
			heat = clamp(0.90 - UV.y * 0.72 + fire * 0.08, 0.0, 1.0);
			brightness = mix(0.30, 1.0, 1.0 - smoothstep(0.18, 1.05, age));
			if (!FRONT_FACING) brightness *= 0.22;
		} else {
			brightness = mix(0.64, 1.0, impact_peak);
		}
	} else if (surface_kind > 3.5 && surface_kind < 4.5) {
		float patch = noise(cast_position.xz * 1.7);
		heat = 0.43 + patch * 0.30;
		brightness = (0.28 + 0.64 * smoothstep(0.22, 0.78, patch)) * mix(0.77, 1.12, impact_peak);
		mask *= 1.0 - smoothstep(1.78 + patch * 0.24, 2.14 + patch * 0.13, age);
	} else if (surface_kind > 5.5) {
		// SolarStar is an authored outline band; keep it uninterrupted and
		// legible above the subordinate fractured-plate edge network.
		heat = 0.90;
		brightness = mix(0.83, 1.15, impact_peak);
	} else if (surface_kind > 4.5) {
		heat = 0.92;
	} else {
		heat = 1.0;
	}
	vec3 orange = mix(vec3(1.0, 0.022, 0.002), vec3(1.0, 0.25, 0.008), smoothstep(0.0, 0.70, heat));
	orange = mix(orange, vec3(1.0, 0.72, 0.17), smoothstep(0.78, 1.0, heat));
	if (surface_kind < 0.5) orange = vec3(1.0, 0.96, 0.78);
	else if (surface_kind < 1.5) {
		orange = mix(vec3(1.0, 0.15, 0.005), vec3(1.0, 0.65, 0.12), smoothstep(0.25, 0.84, heat));
		orange = mix(orange, vec3(1.0, 0.97, 0.76), impact_peak * smoothstep(0.56, 0.85, heat));
	} else if (surface_kind > 1.5 && surface_kind < 3.5) {
		orange = mix(vec3(0.85, 0.015, 0.001), vec3(1.0, 0.48, 0.035), smoothstep(0.15, 0.90, heat));
	} else if (surface_kind > 3.5 && surface_kind < 4.5) {
		orange = mix(vec3(0.92, 0.070, 0.003), vec3(1.0, 0.46, 0.065), smoothstep(0.40, 0.80, heat));
	} else if (surface_kind > 5.5) {
		orange = mix(vec3(1.0, 0.48, 0.055), vec3(1.0, 0.91, 0.49), impact_peak);
	} else if (surface_kind > 4.5) {
		float ember_grain=noise(cast_position.xz*9.0+cast_position.y*3.0);
		float hot_center=1.0-smoothstep(0.12,0.62,length(UV-vec2(0.5,0.36)));
		orange=mix(vec3(1.0,0.09,0.004),vec3(1.0,0.51,0.045),ember_grain);
		orange=mix(orange,vec3(1.0,0.96,0.57),hot_center*0.86);
		brightness=0.82+0.18*sin(cast_time*17.0+ember_grain*13.0);
	}
	ALBEDO = orange * energy * brightness * opacity * mask;
	EMISSION = vec3(0.0);
	ALPHA = clamp(opacity * mask, 0.0, 1.0);
}
