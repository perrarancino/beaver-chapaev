shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform float trail_length;

varying vec4 shape;
varying vec4 filaments;
varying vec4 heat;

float hash_cell(float cell) {
	float p = fract(cell * 0.1031);
	p *= p + 33.33;
	return fract(p * (p + p));
}

float noise_along(float p) {
	float cell = floor(p);
	float blend = smoothstep(0.0, 1.0, fract(p));
	return mix(hash_cell(cell), hash_cell(cell + 1.0), blend);
}

vec3 heated_color(vec3 tint) {
	return mix(clamp(tint * vec3(1.24, 1.75, 1.35), 0.0, 1.0), vec3(1.0), 0.34);
}

void vertex() {
	// These values vary along the path. The mesh already samples it at each row.
	float along = UV.y;
	float lag = clamp(UV2.y / trail_length, 0.0, 1.0);
	float eddies = noise_along(along * 2.95);
	float bend_fade = smoothstep(0.0, 0.23, lag);
	// UV2.x selects the crisp profile for untinted trails.
	if (UV2.x > 0.5) {
		shape = vec4((eddies - 0.5) * 0.27 * bend_fade, 0.0, mix(0.154, 0.104, lag), 0.0);
		float sway = (eddies - 0.5) * 0.18;
		filaments = vec4(
			(0.48 + sway) * smoothstep(0.10, 0.59, lag),
			-(0.55 - sway * 0.54) * smoothstep(0.17, 0.65, lag),
			smoothstep(0.11, 0.25, lag) * (1.0 - smoothstep(0.54, 0.92, lag)),
			smoothstep(0.18, 0.33, lag) * (1.0 - smoothstep(0.48, 0.79, lag))
		);
		heat = vec4(0.0);
	} else {
		float plumes = noise_along(along * 6.0 + 21.2);
		float tear = noise_along(along * 12.0 + 0.9);
		float bend = ((eddies - 0.5) * 0.66 + 0.052 * sin(along * 9.5)) * bend_fade;
		float width = (0.37 + eddies * 0.26 + plumes * 0.34) * mix(1.0, 0.51, lag);
		shape = vec4(bend, width, 0.105 + plumes * 0.135, tear);

		float streaks = smoothstep(0.07, 0.28, lag);
		filaments = vec4(
			0.22 + 0.32 * plumes,
			-0.24 - 0.14 * sin(along * 14.5),
			streaks * smoothstep(0.19, 0.70, tear),
			streaks * (0.5 + 0.5 * sin(along * 9.0 + TIME * 3.0))
		);
		heat = vec4(heated_color(COLOR.rgb), mix(1.0, 0.23, smoothstep(0.29, 0.84, lag)));
	}
}

vec4 colored_profile(float cross_section, float offset, vec3 tint) {
	float tear = shape.w;
	float contour = shape.y * mix(0.86 + tear * 0.28, 1.15 - tear * 0.31, smoothstep(-0.20, 0.20, offset));
	float body = 1.0 - smoothstep(contour * 0.24, contour, abs(offset));
	float halo = 1.0 - smoothstep(0.08, 0.95, abs(cross_section - shape.x * 0.52));
	float core = (1.0 - smoothstep(0.0, shape.z, abs(offset))) * heat.a;
	float stream_a = 1.0 - smoothstep(0.025, 0.12, abs(offset - filaments.x));
	float stream_b = 1.0 - smoothstep(0.014, 0.076, abs(offset - filaments.y));
	float stream = clamp(stream_a * filaments.z + stream_b * filaments.w, 0.0, 1.0);
	float edge = 1.0 - smoothstep(0.86, 1.0, abs(cross_section));

	vec3 color = mix(tint, heat.rgb, body * 0.47 + stream * 0.39);
	color = mix(color, vec3(1.0), core * 0.88);
	float transmission = (1.0 - 0.46 * halo) * (1.0 - 0.95 * body) * (1.0 - 0.55 * core);
	transmission *= 1.0 - 0.43 * stream;
	return vec4(color, (1.0 - transmission) * edge);
}

void fragment() {
	float cross_section = UV.x * 2.0 - 1.0;
	float offset = cross_section - shape.x;
	vec4 profile;
	if (UV2.x > 0.5) {
		float distance_from_center = abs(offset);
		float core = 1.0 - smoothstep(shape.z * 0.34, shape.z, distance_from_center);
		float rim = 1.0 - smoothstep(shape.z * 0.80, shape.z * 1.77, distance_from_center);
		float width_a = mix(0.023, 0.101, filaments.z);
		float width_b = mix(0.018, 0.083, filaments.w);
		float wisp_a = filaments.z * (1.0 - smoothstep(width_a * 0.18, width_a, abs(offset - filaments.x)));
		float wisp_b = filaments.w * (1.0 - smoothstep(width_b * 0.18, width_b, abs(offset - filaments.y)));
		float transmission = (1.0 - 0.98 * core) * (1.0 - 0.23 * rim);
		transmission *= (1.0 - 0.77 * wisp_a) * (1.0 - 0.62 * wisp_b);
		float glow = max(core, 0.83 * max(wisp_a, wisp_b));
		profile = vec4(vec3(mix(0.83, 1.0, glow)), 1.0 - transmission);
	} else {
		profile = colored_profile(cross_section, offset, COLOR.rgb);
	}
	float front = smoothstep(0.015, 0.14, UV2.y);
	ALBEDO = profile.rgb;
	ALPHA = COLOR.a * profile.a * front;
}
