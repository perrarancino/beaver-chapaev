shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

float blob(vec2 point, vec2 center, vec2 size) {
	return length((point - center) / size) - 1.0;
}

float meld(float a, float b) {
	float blend = max(0.28 - abs(a - b), 0.0) / 0.28;
	return min(a, b) - blend * blend * 0.07;
}

void fragment() {
	vec2 point = UV * 2.0 - 1.0;
	float flow = sin(point.y * 4.0 - TIME * 2.2);
	point.x += flow * 0.045;
	float bridge = blob(point, vec2(0.0), vec2(0.67, 0.37));
	float upper = blob(point, vec2(-0.24, -0.37), vec2(0.31, 0.35));
	float lower = blob(point, vec2(0.16, 0.38), vec2(0.27, 0.38));
	float shape = meld(meld(bridge, upper), lower);
	shape = meld(shape, blob(point, vec2(0.43, -0.21), vec2(0.26, 0.22)));
	float drops = min(blob(point, vec2(-0.36, -0.77), vec2(0.10, 0.095)),
		blob(point, vec2(0.35, 0.72), vec2(0.09, 0.12)));
	shape = min(shape, drops);

	float edge = max(fwidth(shape) * 0.85, 0.014);
	float depth = 1.0 - smoothstep(-0.58, 0.01, shape);
	vec3 slime = mix(vec3(0.075, 0.31, 0.025), vec3(0.42, 0.93, 0.10), depth);
	float shine = 1.0 - smoothstep(-0.14, 0.16, blob(point, vec2(-0.18, -0.16), vec2(0.34, 0.073)));
	float glint = 1.0 - smoothstep(-0.20, 0.16, blob(point, vec2(0.15, 0.36), vec2(0.12, 0.065)));
	ALBEDO = mix(slime, vec3(0.87, 1.0, 0.56), 0.72 * max(shine, glint));
	ALPHA = (1.0 - smoothstep(-edge, edge, shape)) * 0.96;
}
