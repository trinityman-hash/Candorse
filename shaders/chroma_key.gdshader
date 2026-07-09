shader_type spatial;
render_mode blend_mix, cull_disabled, unshaded, depth_draw_always;
// Separate pass from video_compositor.gdshader per Module E: "Chroma key
// as a separate fragment shader pass (basic spill suppression, not a full
// keyer)." Deliberately not merged into the main compositor — chroma key
// is a genuinely different shader-complexity class (the brief calls this
// out explicitly in §7), and forcing every track through key-capable math
// would cost every plain video/overlay track GPU time it doesn't need.
// Applied only to tracks that opt in (foreground/hero tracks doing green
// screen work), same gating philosophy as displacement_curve.gdshader.

uniform sampler2D video_texture : source_color, filter_linear, repeat_disable;
uniform vec4 key_color : source_color = vec4(0.0, 1.0, 0.0, 1.0); // default green screen
uniform float similarity : hint_range(0.0, 1.0) = 0.4; // how close to key_color counts as "keyed out"
uniform float smoothness : hint_range(0.0, 0.5) = 0.08; // edge feather width
uniform float spill_suppress : hint_range(0.0, 1.0) = 0.5; // desaturate key-colored spill on kept pixels
uniform float opacity : hint_range(0.0, 1.0) = 1.0;

// YCbCr chroma distance rather than raw RGB distance: keying on chroma
// (not luma) makes the key far less sensitive to lighting/shadow falloff
// across the green screen, which is the single biggest practical failure
// mode of a naive RGB-distance keyer. This is still explicitly the
// "basic" keyer per Module E — no light wrap, no despill-via-neighbor-
// sampling, no edge blur beyond the single smoothstep band below.
vec2 rgb_to_cbcr(vec3 c) {
	float y = dot(c, vec3(0.299, 0.587, 0.114));
	float cb = (c.b - y) * 0.564;
	float cr = (c.r - y) * 0.713;
	return vec2(cb, cr);
}

void fragment() {
	vec4 tex_color = texture(video_texture, UV);

	vec2 cbcr = rgb_to_cbcr(tex_color.rgb);
	vec2 key_cbcr = rgb_to_cbcr(key_color.rgb);
	float chroma_dist = distance(cbcr, key_cbcr);

	// alpha: 0 where fully keyed out, 1 where fully kept, feathered by
	// `smoothness` across the similarity threshold.
	float alpha = smoothstep(similarity, similarity + smoothness, chroma_dist);

	// Basic spill suppression: on partially-kept edge pixels, pull the
	// dominant key-colored channel toward the average of the other two,
	// scaled by how close this pixel's chroma is to the key (so fully-kept
	// interior pixels are untouched, only the fringe gets desaturated).
	vec3 despilled = tex_color.rgb;
	float spill_amount = (1.0 - smoothstep(similarity, similarity + smoothness * 3.0, chroma_dist)) * spill_suppress;
	if (key_color.g > key_color.r && key_color.g > key_color.b) {
		float avg_rb = (despilled.r + despilled.b) * 0.5;
		despilled.g = mix(despilled.g, min(despilled.g, avg_rb), spill_amount);
	} else if (key_color.b > key_color.r && key_color.b > key_color.g) {
		float avg_rg = (despilled.r + despilled.g) * 0.5;
		despilled.b = mix(despilled.b, min(despilled.b, avg_rg), spill_amount);
	}

	ALBEDO = despilled;
	ALPHA = alpha * tex_color.a * opacity;
}
