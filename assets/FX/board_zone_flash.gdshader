shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

uniform sampler2D noise_texture : filter_linear_mipmap, repeat_enable;
uniform vec4 tint : source_color;
uniform float strength = 1.0;
uniform float progress;

float band(float distance_to_curve, float width) {
	return 1.0 - smoothstep(0.0, width, abs(distance_to_curve));
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.8;
	float radius = length(p);
	vec3 detail = texture(noise_texture, p * 0.78 + progress * 0.23).rgb;
	float fade = 1.0 - progress;
	float wave_radius = mix(0.10, 1.19, 1.0 - fade * fade);
	float wave = radius - wave_radius + 0.16 * (detail.r - 0.5);
	float ripple = (band(wave, 0.078) + 0.36 * band(wave + 0.16, 0.054))
		* fade * mix(0.37, 1.0, detail.g);
	float core = (1.0 - smoothstep(0.035, 0.48, radius)) * fade * fade;
	float spray = smoothstep(0.68, 0.90, detail.b) * band(wave - 0.12, 0.18) * fade;
	vec3 reflection = mix(tint.rgb, vec3(1.0, 0.95, 0.83), 0.76);
	ALBEDO = mix(tint.rgb, reflection, clamp(0.82 * ripple + core + spray, 0.0, 1.0));
	ALPHA = clamp((ripple * 0.96 + core * 0.68 + spray) * strength, 0.0, 0.91);
}
