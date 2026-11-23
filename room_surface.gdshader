shader_type spatial;

uniform vec4 base_color : source_color;
uniform float wear : hint_range(0.0, 1.0) = 0.0;

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float grain(vec3 point) {
	return fract(sin(dot(point, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

float mottling(vec3 point) {
	vec3 cell = floor(point);
	vec3 blend = smoothstep(vec3(0.0), vec3(1.0), fract(point));
	float bottom = mix(
		mix(grain(cell), grain(cell + vec3(1, 0, 0)), blend.x),
		mix(grain(cell + vec3(0, 1, 0)), grain(cell + vec3(1, 1, 0)), blend.x), blend.y);
	float top = mix(
		mix(grain(cell + vec3(0, 0, 1)), grain(cell + vec3(1, 0, 1)), blend.x),
		mix(grain(cell + vec3(0, 1, 1)), grain(cell + vec3(1, 1, 1)), blend.x), blend.y);
	return mix(bottom, top, blend.z);
}

void fragment() {
	float stains = mottling(world_position * vec3(4.2, 1.8, 4.2));
	float pitting = mottling(world_position * 41.0);
	ALBEDO = base_color.rgb * (1.0 + wear * (1.35 * stains + 0.4 * pitting - 0.91));
	ROUGHNESS = mix(0.69, 0.93, stains);

#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	// Dither the lighting before the dark gradient is rounded to framebuffer colors.
	vec2 pixel = floor(FRAGCOORD.xy);
	float noise = fract(52.9829189 * fract(dot(pixel, vec2(0.06711056, 0.00583715))));
	EMISSION = vec3((noise - 0.5) * 0.012);
#endif
}
