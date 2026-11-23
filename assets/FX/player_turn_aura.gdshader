shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D aura_texture : source_color, filter_linear_mipmap, repeat_disable;

varying vec2 aura_uv;

void vertex() {
	float angle = TIME * 0.72;
	float c = cos(angle);
	float s = sin(angle);
	mat2 spin = mat2(vec2(c, s), vec2(-s, c));
	aura_uv = spin * (UV - vec2(0.5)) + vec2(0.5);
}

void fragment() {
	vec4 aura = texture(aura_texture, aura_uv);
	ALBEDO = aura.rgb * 1.03;
	ALPHA = aura.a * (0.76 + 0.06 * sin(TIME * 2.0));
}
