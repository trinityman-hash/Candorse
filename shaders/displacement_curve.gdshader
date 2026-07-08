shader_type spatial;
render_mode blend_mix, cull_disabled;
// Gated to foreground/hero tracks only per §3 correction — background tracks
// should use video_compositor.gdshader directly without this vertex pass.

uniform sampler2D video_texture : source_color, filter_linear;
uniform float curl_amount : hint_range(0.0, 1.0) = 0.0; // 0 = flat, mirrors Module E cylinder wrap
uniform float curl_radius : hint_range(0.1, 10.0) = 2.0;

// TODO Phase 3: page-curl and ripple/noise UV displacement are separate
// vertex functions per Module E — implemented as geometry motion, not pure
// shader crossfade, when the visual requires real mesh deformation.

void vertex() {
	if (curl_amount > 0.0) {
		float angle = VERTEX.x / curl_radius * curl_amount;
		vec3 curled;
		curled.x = sin(angle) * curl_radius;
		curled.y = VERTEX.y;
		curled.z = (1.0 - cos(angle)) * curl_radius * -1.0;
		VERTEX = mix(VERTEX, curled, curl_amount);

		// A cylinder wrap around the Y axis rotates the surface normal by
		// the same `angle` as the vertex — the flat quad's incoming normal
		// (0, 0, 1) becomes (sin(angle), 0, cos(angle)) at full curl.
		// Without this, lighting on curved tracks reads as flat-shaded
		// once Module D's lit render path replaces `unshaded` — the bend
		// would be geometrically real but visually look unlit/wrong.
		vec3 curled_normal = vec3(sin(angle), NORMAL.y, cos(angle));
		NORMAL = normalize(mix(NORMAL, curled_normal, curl_amount));
	}
}

void fragment() {
	vec4 tex_color = texture(video_texture, UV);
	ALBEDO = tex_color.rgb;
	ALPHA = tex_color.a;
}
