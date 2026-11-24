shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled, depth_draw_never;

// Each crest has a soft leading edge and a wider trailing slope.
float ripple(float radius, float angle, float age, float delay, float phase) {
	float t = clamp((age - delay) / (1.0 - delay), 0.0, 1.0);
	float travel = t * (1.64 - 0.64 * t);
	float bend = 0.045 * sin(3.0 * angle + phase)
		+ 0.022 * sin(7.0 * angle - phase + 1.4 * t);
	float offset = radius - (0.09 + 0.82 * travel + bend * travel);
	float width = mix(0.058, 0.029, travel) + max(fwidth(radius), 0.002);
	float slope = offset / (width * mix(1.65, 0.85, smoothstep(-width, width, offset)));
	float patches = sin(2.0 * angle + phase) + 0.7 * sin(5.0 * angle - phase + t);
	float coverage = mix(1.0, smoothstep(-1.3, 0.4, patches), 0.86 * travel);
	return exp(-slope * slope) * coverage * smoothstep(0.0, 0.085, t)
		* (1.0 - smoothstep(0.48, 1.0, t));
}

void fragment() {
	float age = clamp(COLOR.r, 0.0, 1.0);
	vec2 p = UV * 2.0 - 1.0;
	float fade = 1.0 - smoothstep(0.03, 0.40, age);
	// A compact contact glint gives way to the airborne chips.
	vec2 core_uv = p * vec2(5.4, 7.2);
	float core = exp(-dot(core_uv, core_uv));
	vec2 streak_uv = abs(p) * vec2(2.9, 14.0);
	float streak = exp(-dot(streak_uv, streak_uv));
	vec2 cross_uv = abs(p) * vec2(18.0, 4.6);
	float cross_light = exp(-dot(cross_uv, cross_uv));
	float light = max(core, max(streak, cross_light * 0.72) * (1.0 - age));
	float radius = length(p);
	float angle = atan(p.y, p.x + 0.00001);
	float wave = ripple(radius, angle, age, 0.0, 0.6) * 0.86
		+ ripple(radius, angle, age, 0.23, 3.7) * 0.67;
	float glint = light * fade;
	vec3 spark = mix(vec3(1.05, 0.39, 0.06), vec3(2.1, 1.75, 1.05), core);
	float mist = min(wave, 1.0) * (1.0 - glint);
	ALPHA = glint + mist;
	ALBEDO = (spark * glint + vec3(1.40, 0.88, 0.42) * mist) / max(glint + mist, 0.001);
}
