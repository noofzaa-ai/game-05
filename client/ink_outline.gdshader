shader_type spatial;
// An ink outline: the mesh is drawn again, slightly fatter, with only its back faces showing in a dark
// ink color. Put it in a material's "next pass" (or use it as a mesh overlay).
// The line is kept between min_pixels and max_pixels thick, so it stays even near and far. Characters
// draw it on a copy of their mesh with averaged normals (InkStyle.outline_mesh) so it does not tear.
render_mode cull_front, unshaded, shadows_disabled;

uniform vec4 ink_color : source_color = vec4(0.07, 0.07, 0.09, 1.0);
uniform float width = 0.005;  // in the mesh's own units, before the pixel limits
uniform float min_pixels = 0.0;
uniform float max_pixels = 2.2;

void vertex() {
	vec3 direction = normalize(NORMAL);
	// How big one pixel is at this vertex's distance, then the line's width in pixels, kept in range.
	// (Pushed in 3D, not on the screen: the web renderer ignores a written POSITION.)
	float units_to_view = max(length(mat3(MODELVIEW_MATRIX) * direction), 0.000001);  // any scale on the way
	float depth = max(-(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z, 0.0001);
	float pixel_size = 2.0 / (abs(PROJECTION_MATRIX[1][1]) * max(VIEWPORT_SIZE.y, 1.0));
	if (PROJECTION_MATRIX[3][3] < 0.5) {
		pixel_size *= depth;  // perspective: farther = bigger pixels
	}
	float pixels = clamp(width * units_to_view / pixel_size, min_pixels, max_pixels);
	VERTEX += direction * pixels * pixel_size / units_to_view;
}

void fragment() {
	ALBEDO = ink_color.rgb;
}
