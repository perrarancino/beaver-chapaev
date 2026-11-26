shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

uniform sampler2D noise_texture : filter_linear_mipmap, repeat_enable;
uniform int kind;
uniform vec4 tint : source_color;
uniform vec2 radii = vec2(0.5);
uniform vec2 stream_axis = vec2(1.0, 0.0);
uniform float shape_phase;
uniform float impact;
uniform float reveal = 1.0;

varying vec2 field;
varying float outline_distance;

void vertex() {
	field = VERTEX.xz / radii;
	outline_distance = UV2.x - 1.0;
}

float band(float distance_to_curve, float width) {
	return 1.0 - smoothstep(0.0, width, abs(distance_to_curve));
}

vec2 rotate_field(vec2 p, vec2 axis) {
	return vec2(p.x * axis.x - p.y * axis.y, p.x * axis.y + p.y * axis.x);
}

void fragment() {
	float time = TIME + shape_phase * 3.0;
	float radius = length(field);

	// Reuse the same tile for the motion field, dye, highlight, and flecks.
	vec2 flow = texture(noise_texture, field * 0.23 + vec2(0.018, -0.024) * time).rg - 0.5;
	vec2 fluid = field + flow * 0.34;
	vec2 detail_uv = fluid * 0.56 + vec2(-0.024, 0.029) * time;
	vec3 secondary = tint.rgb;
	if (kind == 0) {
		float turn = radius * 6.4 - time * 0.75;
		detail_uv = rotate_field(fluid, vec2(cos(turn), sin(turn))) * vec2(0.43, 0.86) + time * 0.043;
		secondary = vec3(0.26, 0.53, 1.0);
	} else if (kind == 1) {
		detail_uv = rotate_field(fluid, stream_axis) * vec2(1.08, 0.26) + vec2(0.0, time * 0.43);
		secondary = vec3(1.0, 0.37, 0.08);
	} else if (kind == 2) {
		detail_uv = fluid * 0.83 - vec2(0.027, 0.041) * time;
		secondary = vec3(0.48, 0.26, 0.95);
	} else {
		secondary = kind == 3 ? vec3(0.07, 0.47, 0.65) : vec3(0.43, 0.61, 0.078);
	}

	vec3 detail = texture(noise_texture, detail_uv).rgb;
	float body = mix(detail.r, detail.g, 0.30);
	float light = 0.0;
	if (kind == 0) {
		float depth = mix(0.43, 1.0, smoothstep(0.03, 0.55, radius));
		body *= depth;
		light = smoothstep(0.27, 0.87, body);
	} else if (kind == 1) {
		light = smoothstep(0.39, 0.86, detail.r) * mix(0.53, 1.0, detail.g);
	} else if (kind == 2) {
		light = band(detail.r - 0.51, 0.075) * mix(0.46, 0.95, detail.g);
	} else {
		float direction = kind == 3 ? 1.0 : -1.0;
		float wave = sin(radius * 16.0 + time * 1.9 * direction + body * (kind == 3 ? 3.4 : 5.7));
		light = smoothstep(0.36, 1.0, wave) * mix(0.31, 0.88, detail.r);
		body = mix(body, wave * 0.5 + 0.5, 0.39);
	}

	float edge = outline_distance + 0.027 * (detail.b - 0.5);
	float rim = band(edge + 0.012, 0.050) * mix(0.49, 1.0, detail.g);
	float flecks = smoothstep(0.79, 0.95, detail.b) * 0.44;
	float pulse = band(outline_distance + 0.31 * impact, 0.092) * impact;
	vec3 reflection = mix(tint.rgb, vec3(1.0, 0.95, 0.83), 0.76);
	vec3 pool = mix(secondary * 0.23, tint.rgb, smoothstep(0.0, 0.92, body));
	float opening = 1.0 - smoothstep(0.0, 0.25, radius - reveal * 1.60 - flow.x * 0.17);
	float highlight = light * 0.56 + rim * 0.66 + flecks + pulse * 0.54;
	ALBEDO = mix(pool, reflection, clamp(highlight, 0.0, 1.0)) * mix(0.46, 1.0, opening);
}
