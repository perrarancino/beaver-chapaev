shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, shadows_disabled, fog_disabled;

uniform bool icy = false;
uniform bool electric = false;
uniform sampler2D arc_atlas : source_color, filter_linear, repeat_disable;

varying vec2 radial;
varying float height;

void vertex() {
	radial = VERTEX.xz;
	height = clamp(VERTEX.y / 0.118 + 0.5, 0.0, 1.0);
}

void fragment() {
	float angle = atan(radial.y, radial.x);
	if (electric) {
		float segment = angle * (4.0 / TAU) - TIME * 0.52;
		float sector = floor(segment);
		float u = fract(segment);
		float frame = mod(floor(TIME * 9.0) + sector, 2.0);
		float v = (height - 0.55 - 0.10 * sin(TIME * 3.8 + sector * 1.7)) * 1.28 + 0.5;
		vec4 arc = texture(arc_atlas, vec2((frame + u) / 3.0, clamp(v, 0.0, 1.0)));
		float flicker = 0.60 + 0.40 * sin(TIME * 7.0 + sector * 1.55);
		ALBEDO = arc.rgb * vec3(0.68, 0.90, 1.18) * 1.15;
		ALPHA = arc.a * flicker * 0.84;
	} else {
		float sway = sin(TIME * 3.7 + angle * 4.0) * 0.55;
		float ridges = sin(angle * 8.0 + sway - height * 4.0);
		float variation = sin(angle * 3.0 - TIME * 2.7 + height * 2.0);
		float tip = 0.46 + 0.46 * pow(max(0.0, ridges), 2.0) + 0.06 * variation;
		float edge = 1.0 - smoothstep(tip - 0.13, tip, height);
		float heat = (1.0 - height) * (0.73 + 0.27 * ridges);
		vec3 outer_color = icy ? vec3(0.12, 0.49, 0.90) : vec3(1.0, 0.16, 0.032);
		vec3 core_color = icy ? vec3(0.70, 0.96, 1.0) : vec3(1.0, 0.76, 0.31);
		ALBEDO = mix(outer_color, core_color, smoothstep(0.16, 0.64, heat));
		ALPHA = smoothstep(0.08, 0.38, height) * edge * (0.61 + 0.15 * variation);
	}
}
