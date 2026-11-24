shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform float arrow_length = 1.0;
uniform vec4 edge_color : source_color = vec4(0.035, 0.18, 0.20, 1.0);
uniform vec4 shaft_color : source_color = vec4(0.27, 0.78, 0.73, 1.0);
uniform vec4 tip_color : source_color = vec4(0.76, 1.0, 0.94, 1.0);

varying vec2 local_point;

void vertex() {
	local_point = VERTEX.xz;
}

void fragment() {
	vec2 point = vec2(local_point.x, (local_point.y + 0.5) * arrow_length);
	float tip = arrow_length - 0.026;
	float head_length = min(0.25, arrow_length * 0.56);
	float head_base = tip - head_length;
	float head_width = min(0.116, arrow_length * 0.33);
	float shaft_width = mix(0.019, 0.035, smoothstep(0.0, head_base, point.y));
	float shaft = max(abs(point.x) - shaft_width, max(0.026 - point.y, point.y - head_base - 0.024));
	float head_side = (abs(point.x) * head_length - (tip - point.y) * head_width)
		/ length(vec2(head_length, head_width));
	float shape = min(shaft, max(head_base - point.y, head_side));

	float aa = max(fwidth(shape) * 0.65, 0.001);
	float fill = 1.0 - smoothstep(-aa, aa, shape);
	float outline = 1.0 - smoothstep(0.010 - aa, 0.010 + aa, shape);
	float fade = mix(0.48, 1.0, smoothstep(0.024, min(head_base, 0.30), point.y));
	vec3 color = mix(shaft_color.rgb, tip_color.rgb, smoothstep(head_base, tip, point.y));
	ALBEDO = mix(edge_color.rgb, color * (1.0 + 0.55 * pow(0.5 + 0.5 * cos(point.y * 17.0 - TIME * 8.0), 5.0)), fill);
	ALPHA = outline * fade;
}
