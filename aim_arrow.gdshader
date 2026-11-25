shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform float arrow_length = 1.0;
uniform float pull_amount : hint_range(0.0, 1.0) = 0.0;

varying vec2 local_point;

void vertex() {
	local_point = VERTEX.xz;
}

void fragment() {
	vec2 point = vec2(local_point.x, (local_point.y + 0.5) * arrow_length);
	float tip = arrow_length - 0.026;
	float head_length = min(0.27, arrow_length * 0.51);
	float head_base = tip - head_length;
	float head_width = min(0.128, arrow_length * 0.34);
	float shaft_width = mix(0.020, 0.044, smoothstep(0.026, head_base, point.y));
	float shaft = max(abs(point.x) - shaft_width, max(0.026 - point.y, point.y - head_base - 0.018));
	float head_side = (abs(point.x) * head_length - (tip - point.y) * head_width)
		/ length(vec2(head_length, head_width));
	float shape = min(shaft, max(head_base - point.y, head_side));

	float aa = max(fwidth(shape) * 0.65, 0.001);
	float fill = 1.0 - smoothstep(-aa, aa, shape);
	float outline = 1.0 - smoothstep(0.012 - aa, 0.012 + aa, shape);
	float fade = mix(0.66, 1.0, smoothstep(0.024, min(head_base, 0.26), point.y));
	vec3 green = vec3(0.21, 0.99, 0.34);
	vec3 amber = vec3(1.0, 0.76, 0.065);
	vec3 red = vec3(1.0, 0.14, 0.085);
	vec3 power_color = mix(green, amber, clamp(pull_amount * 2.0, 0.0, 1.0));
	power_color = mix(power_color, red, clamp(pull_amount * 2.0 - 1.0, 0.0, 1.0));
	float highlight = (1.0 - smoothstep(0.0, 0.048, abs(point.x))) * 0.13;
	highlight += smoothstep(head_base, tip, point.y) * 0.22;
	vec3 color = mix(power_color * mix(0.71, 1.0, smoothstep(0.02, head_base, point.y)),
		vec3(1.0, 0.97, 0.88), highlight);
	ALBEDO = mix(power_color * 0.22, color, fill);
	ALPHA = outline * fade;
}
