shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;

uniform vec4 tint : source_color = vec4(0.22, 0.12, 0.065, 0.62);
uniform sampler2D smoke_texture : source_color, filter_linear_mipmap;
uniform bool use_texture = false;
uniform float smoke_kind = 0.0; // volume 0, fine fringe 1, broad billow card 2
uniform float cast_time = 0.0;
uniform float impact_time = 1.12;
uniform float opacity = 1.0;
// Optional receiver visibility for the spear catch. Other skills keep zero.
uniform vec3 receiver_world = vec3(0.0);
uniform float receiver_radius = 1.0;
uniform float receiver_visibility = 0.0;
varying vec3 cloud_position;

void vertex() {
	cloud_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
void fragment() {
	float age = max(0.0, cast_time - impact_time);
	// Closed volumes draw their outward wall once. The intersecting puff
	// cards remain double-sided so their deliberately torn silhouettes work.
	if (smoke_kind < 0.5 && !FRONT_FACING) discard;
	vec2 world_curl = vec2(noise(cloud_position.xz * 0.62), noise(cloud_position.xz * 0.62 + vec2(6.3, 1.7)));
	vec2 curl_uv = UV * vec2(2.7, 2.25) + world_curl * 1.10 + vec2(age * 0.10, -age * 0.12);
	float curl = noise(curl_uv + vec2(0.0, noise(curl_uv * 0.83) * 0.55));
	float n = curl * 0.87 + noise(curl_uv * 2.1 - age * 0.10) * 0.13;
	float silhouette = 1.0;
	if (use_texture) {
		float texture_shape = texture(smoke_texture, UV).a;
		// A broad opaque-looking center and a narrow curved rim, rather than
		// lowering alpha uniformly across every overlapping cloud layer.
		silhouette = smoothstep(0.025, smoke_kind > 1.5 ? 0.30 : 0.55, texture_shape);
	}
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float center_mass = smoothstep(0.22, 0.72, facing);
	float outline_noise = noise(UV * vec2(7.2, 5.7) + world_curl * 1.65 + vec2(curl * 1.4, age * 0.17));
	outline_noise = outline_noise * 0.74 + noise(UV * 13.0 - vec2(age * 0.14)) * 0.26;
	if (!use_texture) {
		// Start breaking the volume contour while retaining dense middle
		// faces. The geometric ellipsoid edge must not read as a solid plate.
		float ragged_facing = facing + (outline_noise - 0.50) * 0.22;
		silhouette *= smoothstep(0.035, 0.43, ragged_facing);
		float boundary_cut = mix(0.51, 0.065, center_mass);
		silhouette *= smoothstep(boundary_cut - 0.18, boundary_cut + 0.10, outline_noise);
	} else {
		// Supporting curl cards blend into the mass. A radial feather hides
		// repeated flower-shaped texture edges rather than tracing each petal.
		float card_radius = length(UV - vec2(0.5)) * 2.0;
		silhouette *= 1.0 - smoothstep(0.25, 0.97, card_radius + (0.5 - n) * 0.16);
	}
	float burning = 1.0 - smoothstep(0.72, 2.16, age);
	float shade = smoothstep(0.19, 0.83, n);
	float volume_light = clamp(dot(normalize(NORMAL), normalize(vec3(-0.52, 0.65, 0.55))) * 0.55 + 0.52, 0.12, 1.0);
	float shape_light = smoke_kind < 0.5 ? mix(0.41, 1.0, volume_light) : 0.83;
	vec3 ash = mix(vec3(0.090, 0.026, 0.007), vec3(0.36, 0.13, 0.027), shade);
	vec3 hot_cloud = mix(vec3(0.30, 0.045, 0.002), vec3(0.93, 0.28, 0.020), shade);
	ALBEDO = mix(ash, hot_cloud, burning) * shape_light;
	// Broad cells erode at different times. Remaining islands keep their
	// full authored size and drift apart instead of shrinking into marbles.
	float group_bias = noise(cloud_position.xz * 0.47) * 0.24;
	float breakup_start = use_texture ? 0.73 : mix(0.25, 0.82, center_mass);
	float breakup_end = use_texture ? 1.78 : mix(1.60, 1.86, center_mass);
	float breakup = smoothstep(breakup_start + group_bias * 0.40, breakup_end + group_bias * 0.50, age);
	float threshold = mix(0.025, 0.91, breakup);
	// A narrow transition erodes holes through the visible mass. The old
	// wide, late threshold only softened alpha on a still-complete ellipsoid.
	float erosion = smoothstep(threshold - 0.055, threshold + 0.055, n);
	if (smoke_kind > 0.5 && smoke_kind < 1.5) {
		erosion *= smoothstep(0.13, 0.48, n);
		ALBEDO = mix(ash, hot_cloud, burning * 0.77);
	}
	vec3 camera_world = INV_VIEW_MATRIX[3].xyz;
	vec3 to_receiver = receiver_world - camera_world;
	float receiver_depth = max(length(to_receiver), 0.001);
	vec3 ray = to_receiver / receiver_depth;
	float along = dot(cloud_position - camera_world, ray);
	float distance_to_ray = length(cloud_position - (camera_world + ray * along));
	float receiver_gap = (1.0 - smoothstep(receiver_radius * 0.65, receiver_radius, distance_to_ray))
		* step(0.0, along) * (1.0 - smoothstep(receiver_depth, receiver_depth + receiver_radius, along));
	ALPHA = clamp(tint.a * opacity * silhouette * erosion * (1.0 - receiver_gap * receiver_visibility), 0.0, 0.96);
}
