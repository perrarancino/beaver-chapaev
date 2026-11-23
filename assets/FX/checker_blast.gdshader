shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, shadows_disabled;

uniform float progress = 0.0;
uniform bool pressure_wave = false;

varying float puff_age;
varying float puff_seed;
varying float core;
varying vec3 shape_point;

void vertex() {
	shape_point = VERTEX;
	if (pressure_wave) {
		float reach = 1.0 - pow(1.0 - progress, 4.0);
		VERTEX.xz *= mix(0.18, 1.19, reach);
		VERTEX.y *= 0.49;
		VERTEX.y += 0.018 * reach;
		puff_age = progress;
		puff_seed = 0.0;
		core = 0.0;
	} else {
		puff_seed = INSTANCE_CUSTOM.x;
		core = INSTANCE_CUSTOM.w;
		puff_age = clamp((progress - puff_seed * 0.09 * (1.0 - core)) / 0.91, 0.0, 1.0);
		float bloom = 1.0 - pow(1.0 - puff_age, 2.8);
		float lobes = sin(VERTEX.x * 5.0 + puff_seed * 14.0)
			* cos(VERTEX.z * 5.0 + VERTEX.y * 4.0 - puff_seed * 10.0);
		float radius = mix(0.095, 0.22 + puff_seed * 0.08, bloom);
		radius *= mix(1.0, 1.32 - 0.45 * puff_age, core);
		VERTEX *= radius * (1.0 + lobes * 0.20);
		VERTEX.y *= mix(0.9, 1.05, puff_seed);
		VERTEX.x += INSTANCE_CUSTOM.y * bloom;
		VERTEX.y += 0.052 + INSTANCE_CUSTOM.z * pow(puff_age, 0.74);
	}
}

void fragment() {
	float face = clamp(dot(normalize(NORMAL), VIEW), 0.0, 1.0);
	if (pressure_wave) {
		ALBEDO = mix(vec3(0.95, 0.30, 0.09), vec3(1.0, 0.74, 0.38), face);
		ALPHA = (1.0 - smoothstep(0.10, 0.53, puff_age)) * (0.22 + face * 0.35);
	} else {
		float lobe = 0.5 + 0.5 * sin(dot(shape_point, vec3(7.0, 5.0, 9.0)) + puff_seed * 21.0);
		float hot = (1.0 - smoothstep(0.10, 0.55 - core * 0.22, puff_age));
		float white_heat = core * (1.0 - smoothstep(0.08, 0.28, puff_age));
		float lit = clamp(0.50 + shape_point.y * 0.28 + lobe * 0.18, 0.05, 1.0);
		vec3 smoke = mix(vec3(0.16, 0.12, 0.12), vec3(0.43, 0.34, 0.30), lit);
		vec3 flame = mix(vec3(1.0, 0.16, 0.033), vec3(1.0, 0.68, 0.23), lit);
		ALBEDO = mix(smoke, flame, hot) + vec3(1.2, 0.73, 0.34) * white_heat;
		float dissolve = 1.0 - smoothstep(0.34 + lobe * 0.12, 1.0, puff_age);
		float fade_in = smoothstep(0.0, 0.12, puff_age + core * 0.06);
		ALPHA = mix(0.38, 0.75, hot) * smoothstep(0.06, 0.60, face) * dissolve * fade_in;
	}
}
