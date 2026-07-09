shader_type spatial;
render_mode blend_mix, cull_disabled, unshaded, depth_draw_always;
// Module E transitions, case (a): "shader crossfade between two sampled
// tracks." VideoTrackMesh swaps into this material only during a clip's
// transition window (see Clip.transition_duration in timeline_data.gd)
// and swaps back to video_compositor.gdshader once the blend completes --
// this shader is not the default per-track material, it's a temporary
// mode. Case (b), geometry transitions like page-curl, is a deliberately
// separate system (displacement_curve.gdshader's vertex-bend path plus
// real mesh motion), not forced through this shader family — per the
// brief's explicit instruction not to conflate the two.

uniform sampler2D texture_out : source_color, filter_linear, repeat_disable;
uniform sampler2D texture_in : source_color, filter_linear, repeat_disable;
uniform float blend : hint_range(0.0, 1.0) = 0.0; // 0 = fully texture_out, 1 = fully texture_in
uniform float opacity : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec4 out_color = texture(texture_out, UV);
	vec4 in_color = texture(texture_in, UV);

	// Straight-alpha mix, same non-premultiplied convention as
	// video_compositor.gdshader — see that file's note on why ALBEDO
	// must not be pre-multiplied by ALPHA when using blend_mix.
	vec3 mixed_rgb = mix(out_color.rgb, in_color.rgb, blend);
	float mixed_alpha = mix(out_color.a, in_color.a, blend);

	ALBEDO = mixed_rgb;
	ALPHA = mixed_alpha * opacity;
}
