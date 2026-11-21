shader_type spatial;

uniform sampler2D wood_grain : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 honey : source_color = vec4(0.66, 0.49, 0.30, 1.0);

varying vec3 board_position;

void vertex() {
	board_position = VERTEX;
}

void fragment() {
	vec2 grain_uv = vec2(board_position.x * 1.18, board_position.z * 0.43);
	vec3 grain = texture(wood_grain, grain_uv).rgb;
	float luminance = dot(grain, vec3(0.2126, 0.7152, 0.0722));
	float patina = clamp(luminance * 1.42 - 0.085, -0.13, 0.12);
	ALBEDO = honey.rgb * (1.0 + patina);
	ROUGHNESS = clamp(0.62 - patina * 0.66, 0.54, 0.73);

#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	// Keep the grid and light pieces readable under the warmer Compatibility lighting.
	ALBEDO *= vec3(0.69, 0.74, 0.86);
#endif
}
