shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, shadows_disabled, fog_disabled;

uniform float trace_clock;
uniform float lifetime;
uniform float stamp_length;
uniform sampler2D stroke_atlas : source_color, filter_linear_mipmap, repeat_disable;

varying float melt;
varying float tile;
varying float path_distance;

void vertex() {
	float elapsed = trace_clock - INSTANCE_CUSTOM.r;
	elapsed += elapsed < -4.0 ? 8.0 : 0.0;
	melt = clamp(elapsed / lifetime, 0.0, 1.0);
	tile = INSTANCE_CUSTOM.g;
	path_distance = INSTANCE_CUSTOM.b + VERTEX.x * stamp_length;
}

void fragment() {
	vec2 atlas_uv;
	float coverage;
	if (abs(tile) < 0.5) {
		float along = 1.0 - abs(fract(path_distance / 1.56) * 2.0 - 1.0);
		atlas_uv = vec2(mix(0.025, 0.978, along), mix(0.153, 0.404, UV.y));
		coverage = 1.0 - abs(UV.x * 2.0 - 1.0);
	} else {
		float end = tile < 0.0 ? 1.0 - UV.x : UV.x;
		atlas_uv = vec2(mix(0.53, 0.942, end), mix(0.618, 0.869, UV.y));
		coverage = smoothstep(0.0, 0.32, end);
	}
	vec4 frost = texture(stroke_atlas, atlas_uv);
	float remaining = 1.0 - smoothstep(0.12 + frost.b * 0.19, 1.0, melt);
	float glint = pow(0.5 + 0.5 * cos(path_distance * 17.0 - trace_clock * TAU), 8.0);
	ALBEDO = frost.rgb + vec3(0.20, 0.48, 0.75) * glint * remaining * frost.b;
	ALPHA = 1.0 - pow(1.0 - frost.a * remaining * 0.88, coverage);
}
