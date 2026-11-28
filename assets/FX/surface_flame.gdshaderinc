float flame_hash(vec2 cell) {
	vec3 p = fract(vec3(cell.xyx) * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float flame_noise(vec2 point) {
	vec2 cell = floor(point);
	vec2 weight = fract(point);
	weight = weight * weight * (3.0 - 2.0 * weight);
	return mix(
		mix(flame_hash(cell), flame_hash(cell + vec2(1.0, 0.0)), weight.x),
		mix(flame_hash(cell + vec2(0.0, 1.0)), flame_hash(cell + vec2(1.0)), weight.x),
		weight.y);
}

// Temperature and incandescent seams from two moving scales of flame.
vec2 surface_flame(vec2 grain, float time, float heat_bias) {
	vec2 flame = grain * vec2(20.0, 15.0) + vec2(time * 0.13, -time);
	float rolling = flame_noise(flame);
	float tongues = flame_noise(flame * 2.1 + vec2(rolling * 1.5, -time * 0.65));
	float flow = rolling * 0.64 + tongues * 0.36;
	float heat = smoothstep(0.40, 0.85, flow + heat_bias);
	float seams = (1.0 - smoothstep(0.016, 0.105, abs(flow - 0.58))) * heat;
	return vec2(heat, seams);
}
