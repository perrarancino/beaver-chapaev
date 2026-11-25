shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

uniform float progress : hint_range(0.0, 1.0) = 0.0;

void vertex() {
	// Orient the puff toward the active camera, including during the fall close-up.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1],
			INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

float puff(vec2 point, vec2 center, float radius) {
	return 1.0 - smoothstep(radius * 0.73, radius, length(point - center));
}

void fragment() {
	vec2 point = vec2(UV.x - 0.5, 0.5 - UV.y);
	vec2 origin = vec2(0.0, -0.10);
	float spread = smoothstep(0.0, 0.90, progress);
	vec2 center = origin + vec2(0.0, spread * 0.20);
	float radius = mix(0.12, 0.20, spread);
	float cloud = puff(point, center, radius);
	for (int i = 0; i < 6; i++) {
		float angle = float(i) * 1.0472 + 0.27;
		vec2 offset = vec2(cos(angle), 0.65 * sin(angle)) * (0.035 + 0.18 * spread);
		float lobe = puff(point, center + offset, radius * (0.89 + 0.14 * cos(angle * 2.0)));
		cloud = 1.0 - (1.0 - cloud) * (1.0 - lobe);
	}
	float smoke = cloud * smoothstep(0.0, 0.12, progress) * (1.0 - smoothstep(0.42, 1.0, progress));
	vec2 spark = abs(point - origin);
	float star = 1.0 - smoothstep(0.85, 1.0, sqrt(spark.x) * 2.0 + sqrt(spark.y) * 2.3);
	float flash = max(star, puff(point, origin, 0.12)) * (1.0 - smoothstep(0.15, 0.48, progress));
	vec3 dust = mix(vec3(0.53, 0.42, 0.34), vec3(0.91, 0.84, 0.72),
			clamp(0.48 + (point.y - center.y) * 2.5, 0.0, 1.0));
	dust = mix(vec3(0.29, 0.19, 0.15), dust, smoothstep(0.12, 0.78, cloud));
	ALBEDO = mix(dust, vec3(1.0, 0.91, 0.62), flash);
	EMISSION = vec3(0.8, 0.45, 0.12) * flash;
	ALPHA = max(smoke, flash);
}
