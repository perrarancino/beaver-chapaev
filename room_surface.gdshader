shader_type spatial;

uniform vec4 base_color : source_color;

void fragment() {
	ALBEDO = base_color.rgb;
	ROUGHNESS = 0.7;

#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	// Dither the lighting before the dark gradient is rounded to framebuffer colors.
	vec2 pixel = floor(FRAGCOORD.xy);
	float noise = fract(52.9829189 * fract(dot(pixel, vec2(0.06711056, 0.00583715))));
	EMISSION = vec3((noise - 0.5) * 0.012);
#endif
}
