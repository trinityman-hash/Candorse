shader_type spatial;
render_mode blend_mix, cull_disabled, unshaded, depth_draw_always;
// unshaded for now: Module D (real lighting on video quads) will switch this
// to a lit render_mode once environment lighting rig lands in Phase 2.

uniform sampler2D video_texture : source_color, filter_linear, repeat_disable;
uniform sampler3D lut_texture : filter_linear;
uniform float lut_strength : hint_range(0.0, 1.0) = 0.0;
uniform vec3 lut_domain_min = vec3(0.0, 0.0, 0.0);
uniform vec3 lut_domain_max = vec3(1.0, 1.0, 1.0);

// DaVinci-style primary wheels. lift pulls shadows up/down without
// clipping highlights, gamma reshapes midtones (power curve), gain
// scales highlights. Standard "lift/gamma/gain" formulation (distinct
// from the ASC CDL slope/offset/power model, though related):
//   lifted = in + lift * (1 - in)
//   graded = pow(lifted, 1 / gamma) * gain
uniform vec3 lift = vec3(0.0, 0.0, 0.0);
uniform vec3 gamma = vec3(1.0, 1.0, 1.0);
uniform vec3 gain = vec3(1.0, 1.0, 1.0);

uniform float brightness : hint_range(-1.0, 1.0) = 0.0;
uniform float contrast : hint_range(0.0, 4.0) = 1.0;
uniform float saturation : hint_range(0.0, 4.0) = 1.0;

// Generic 4x4-ish color matrix, kept for advanced/scripted grading on
// top of the named wheels above. Identity by default (no-op).
uniform vec4 color_matrix_r = vec4(1.0, 0.0, 0.0, 0.0);
uniform vec4 color_matrix_g = vec4(0.0, 1.0, 0.0, 0.0);
uniform vec4 color_matrix_b = vec4(0.0, 0.0, 1.0, 0.0);

// Per-channel tone curves (Master -> Red/Green/Blue), baked CPU-side by
// hsl_curves.gd into a 256x1 lookup: texel x holds (curve_r(x),
// curve_g(x), curve_b(x)) where each already has the Master curve
// folded in. Disabled (uniform bool, so a static branch — cheap on
// mobile) whenever HSLCurves.is_identity() is true, so untouched tracks
// pay zero extra cost. Applied after the color matrix and before the
// LUT, matching the standard grading order: primaries -> curves -> look.
uniform sampler2D hsl_curve_lut : filter_linear, repeat_disable;
uniform bool hsl_curves_enabled = false;

uniform float vignette_strength : hint_range(0.0, 1.0) = 0.0;
uniform float vignette_radius : hint_range(0.0, 1.5) = 0.75;
uniform float vignette_softness : hint_range(0.0, 1.0) = 0.35;

uniform float opacity : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec4 tex_color = texture(video_texture, UV);

	// NOTE on compositing mode: `render_mode blend_mix` performs standard
	// (straight, non-premultiplied) alpha blending using ALBEDO/ALPHA as
	// the source color/coverage — Godot's spatial shaders don't expose a
	// `premultiplied_alpha` render_mode. video_texture is expected to hold
	// straight alpha (true of decoded video frames and typical PNG
	// overlay/sticker/text sources), so ALBEDO must stay un-multiplied
	// here; blend_mix does the alpha compositing itself. Multiplying
	// ALBEDO by alpha on top of that double-darkens every semi-transparent
	// pixel (visible as dark fringing on overlay/text/sticker tracks and,
	// later, chroma-key edges) — that was the bug in the previous version.
	vec3 straight_rgb = tex_color.rgb;

	// --- Lift / Gamma / Gain (primary wheels) ---
	vec3 lifted = clamp(straight_rgb + lift * (vec3(1.0) - straight_rgb), 0.0, 1.0);
	vec3 gamma_safe = max(gamma, vec3(0.001));
	vec3 lgg = pow(lifted, 1.0 / gamma_safe) * gain;

	// --- Brightness / Contrast ---
	vec3 bc = (lgg - 0.5) * contrast + 0.5 + brightness;

	// --- Saturation (luminance-preserving) ---
	float luma = dot(bc, vec3(0.2126, 0.7152, 0.0722));
	vec3 graded_primary = mix(vec3(luma), bc, saturation);

	// --- Generic color matrix (identity by default) ---
	vec4 rgba1 = vec4(graded_primary, 1.0);
	vec3 graded;
	graded.r = dot(rgba1, color_matrix_r);
	graded.g = dot(rgba1, color_matrix_g);
	graded.b = dot(rgba1, color_matrix_b);
	graded = clamp(graded, 0.0, 1.0);

	// --- Per-channel tone curves (see hsl_curves.gd) ---
	if (hsl_curves_enabled) {
		// Each channel looks itself up independently: the lookup texture's
		// R row already has Master->Red folded in at bake time, etc., so
		// this is a direct table lookup, not a further composition step.
		graded.r = texture(hsl_curve_lut, vec2(graded.r, 0.5)).r;
		graded.g = texture(hsl_curve_lut, vec2(graded.g, 0.5)).g;
		graded.b = texture(hsl_curve_lut, vec2(graded.b, 0.5)).b;
		graded = clamp(graded, 0.0, 1.0);
	}

	// --- LUT (domain-remapped, blended in by lut_strength) ---
	vec3 lut_range = max(lut_domain_max - lut_domain_min, vec3(0.0001));
	vec3 lut_uv = clamp((graded - lut_domain_min) / lut_range, 0.0, 1.0);
	vec3 lut_color = texture(lut_texture, lut_uv).rgb;
	vec3 final_rgb = mix(graded, lut_color, lut_strength);

	// --- Vignette ---
	float dist = distance(UV, vec2(0.5));
	float vig = 1.0 - smoothstep(vignette_radius - vignette_softness, vignette_radius, dist);
	final_rgb *= mix(1.0, vig, vignette_strength);

	ALBEDO = final_rgb;
	ALPHA = tex_color.a * opacity;
}
