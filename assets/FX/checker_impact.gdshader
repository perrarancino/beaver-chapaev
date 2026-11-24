shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled, depth_draw_never;

void fragment() {
	float age = COLOR.r;
	vec2 p = UV * 2.0 - 1.0;
	float radius = length(p);
	float angle = atan(p.y, p.x + 0.00001);
	float edge = max(fwidth(radius), 0.012);
	// A broad, asymmetric squash flash breaks into two expanding pressure arcs.
	float teeth = pow(0.5 + 0.5 * cos(7.0 * angle + 0.75 * sin(3.0 * angle)), 4.0);
	float core = (0.32 + 0.46 * teeth) * (1.0 - smoothstep(0.12, 0.72, age));
	float core_dist = radius - core;
	float wave = mix(0.27, 0.91, 1.0 - pow(1.0 - age, 2.0));
	float arc_dist = abs(radius - wave) - mix(0.075, 0.016, age);
	arc_dist = max(arc_dist, 0.24 - abs(p.x) / max(radius, 0.001));
	float dist = min(core_dist, arc_dist);
	float ink = 1.0 - smoothstep(0.018, 0.018 + edge, dist);
	float gold = 1.0 - smoothstep(-edge, edge, dist);
	float white = 1.0 - smoothstep(-0.09, -0.03, core_dist);
	ALBEDO = mix(vec3(0.23, 0.065, 0.012), vec3(2.3, 1.22, 0.24), gold);
	ALBEDO = mix(ALBEDO, vec3(3.0, 2.75, 2.0), white);
	ALPHA = ink * (1.0 - smoothstep(0.56, 1.0, age));
}
