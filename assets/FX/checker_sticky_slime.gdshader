shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

varying vec3 gel_surface;

void vertex() {
	vec3 direction = normalize(VERTEX);
	vec3 wave = vec3(3.0, 1.5, 2.0);
	vec3 ripple = vec3(-4.0, 3.0, 1.0);
	float wave_phase = dot(direction, wave) - TIME * 2.2;
	float ripple_phase = dot(direction, ripple) + TIME * 1.6;
	float swell = 1.0 + 0.075 * sin(wave_phase) + 0.045 * sin(ripple_phase);
	vec3 gradient = wave * (0.075 * cos(wave_phase)) + ripple * (0.045 * cos(ripple_phase));
	vec3 tangent_gradient = gradient - direction * dot(direction, gradient);
	VERTEX *= swell;
	NORMAL = normalize(direction - tangent_gradient / swell);
	gel_surface = direction;
}

void fragment() {
	float upper = smoothstep(-0.75, 0.85, gel_surface.z);
	float flow = sin(gel_surface.x * 6.0 + gel_surface.y * 3.0 - TIME * 2.2);
	float tint = clamp(upper + flow * 0.10, 0.0, 1.0);
	vec3 gel = mix(vec3(0.07, 0.30, 0.025), vec3(0.35, 0.82, 0.075), tint);
	float rim = pow(1.0 - max(dot(normalize(NORMAL), VIEW), 0.0), 3.0);
	ALBEDO = gel;
	ROUGHNESS = 0.27;
	SPECULAR = 0.7;
	EMISSION = gel * (0.13 + rim * 0.24);
}
