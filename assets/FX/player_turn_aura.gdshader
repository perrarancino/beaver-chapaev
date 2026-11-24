shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D frame_texture : source_color, filter_linear_mipmap, repeat_disable;
instance uniform bool is_selected = false;

varying vec2 frame_uv;

void vertex() {
	float angle = TIME * 0.72;
	float cosine = cos(angle);
	float sine = sin(angle);
	mat2 rotation = mat2(vec2(cosine, sine), vec2(-sine, cosine));
	frame_uv = rotation * (UV - vec2(0.5)) + vec2(0.5);
}

void fragment() {
	vec4 frame = texture(frame_texture, frame_uv);
	ALBEDO = frame.rgb * (is_selected ? 1.32 : 1.04);
	ALPHA = frame.a * (is_selected ? 1.0 : 0.82);
}
