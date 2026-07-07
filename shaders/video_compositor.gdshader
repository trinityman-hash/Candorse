shader_type spatial;
render_mode blend_mix, cull_disabled, unshaded, depth_draw_always;
// unshaded for now: Module D (real lighting on video quads) will switch this
// to a lit render_mode once environment lighting rig lands in Phase 2.

uniform sampler2D video_texture : source_color, filter_linear, repeat_disable;
uniform sampler3D lut_texture : filter_linear;
uniform float lut_strength : hint_range(0.0, 1.0) = 0.0;
uniform vec4 color_matrix_r = vec4(1.0, 0.0, 0.0, 0.0);
uniform vec4 color_matrix_g = vec4(0.0, 1.0, 0.0, 0.0);
uniform vec4 color_matrix_b = vec4(0.0, 0.0, 1.0, 0.0);
uniform float opacity : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec4 tex_color = texture(video_texture, UV);

	// Premultiplied-alpha compositing (Module E).
	vec3 straight_rgb = tex_color.rgb;

	// 4x4-ish color matrix grading (using vec4 rows against rgb+1 for offset).
	vec4 rgba1 = vec4(straight_rgb, 1.0);
	vec3 graded;
	graded.r = dot(rgba1, color_matrix_r);
	graded.g = dot(rgba1, color_matrix_g);
	graded.b = dot(rgba1, color_matrix_b);

	// LUT sampling blended in by lut_strength (0 = bypass, cheap default path).
	vec3 lut_color = texture(lut_texture, graded).rgb;
	vec3 final_rgb = mix(graded, lut_color, lut_strength);

	ALBEDO = final_rgb * tex_color.a;
	ALPHA = tex_color.a * opacity;
}
