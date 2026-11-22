shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
const int FLAME_LAYERS = 3;
const int FLAME_SPARKS = 4;
#else
const int FLAME_LAYERS = 9;
const int FLAME_SPARKS = 9;
#endif

float hash(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1137, 0.1379));
	p += dot(p, p.yzx + 19.19);
	return fract((p.x + p.y) * p.z);
}

float noise(vec3 p) {
	vec3 cell = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float near_slice = mix(
		mix(hash(cell), hash(cell + vec3(1, 0, 0)), f.x),
		mix(hash(cell + vec3(0, 1, 0)), hash(cell + vec3(1, 1, 0)), f.x), f.y);
	float far_slice = mix(
		mix(hash(cell + vec3(0, 0, 1)), hash(cell + vec3(1, 0, 1)), f.x),
		mix(hash(cell + vec3(0, 1, 1)), hash(cell + vec3(1, 1, 1)), f.x), f.y);
	return mix(near_slice, far_slice, f.z);
}

float tongue(vec3 p, vec2 origin, float height, float width, float bend) {
	float rise = clamp(p.y / height, 0.0, 1.0);
	float taper = mix(1.0, 0.14, smoothstep(0.0, 1.0, rise));
	vec2 center = origin + vec2(bend * rise, 0.14 * rise);
	vec2 section = vec2(width, width * 1.06) * taper;
	float core = 1.0 - length((p.xz - center) / section);
	return core * (1.0 - smoothstep(height * 0.80, height, p.y));
}

vec3 flame_color(float heat) {
	vec3 red = mix(vec3(0.45, 0.021, 0.002), vec3(2.10, 0.29, 0.012), smoothstep(0.12, 0.58, heat));
	vec3 gold = mix(red, vec3(3.2, 1.35, 0.13), smoothstep(0.48, 0.87, heat));
	return mix(gold, vec3(4.3, 3.1, 1.55), smoothstep(0.80, 1.0, heat));
}

float sparks(vec2 p, float clock, float pixel_width) {
	float result = 0.0;
	for (int index = 0; index < FLAME_SPARKS; index++) {
		float id = float(index);
		float age = fract(clock * (0.30 + 0.29 * hash(vec3(id, 0.5, 4.3))) + hash(vec3(id, 5.0, 1.0)));
		float lifetime = smoothstep(0.05, 0.20, age) * (1.0 - smoothstep(0.55, 0.98, age));
		float spread = hash(vec3(id, 1.5, 9.0)) * 2.0 - 1.0;
		float x = spread * (0.24 + age * 0.16) + 0.10 * sin(clock * 2.3 + id * 2.1) * age;
		float y = 0.16 + age * (0.56 + 0.18 * hash(vec3(id, 6.1, 5.0)));
		float radius = max(0.006 + (1.0 - age) * 0.007, pixel_width);
		float d = length((p - vec2(x, y)) * vec2(0.64, 1.2));
		result = max(result, (1.0 - smoothstep(radius * 0.16, radius, d)) * lifetime);
	}
	return result;
}

void fragment() {
	vec2 p = vec2(UV.x * 2.0 - 1.0, 1.0 - UV.y);
	float clock = TIME * 0.84;
	float lean = 0.15 * sin(clock * 2.2) + 0.13 * sin(clock * 4.7 + p.y * 5.0);
	float left_height = 0.56 + 0.16 * noise(vec3(clock * 1.8, 5.3, 1.0));
	float center_height = 0.74 + 0.17 * noise(vec3(clock * 1.4, 7.1, 6.6));
	float right_height = 0.47 + 0.18 * noise(vec3(clock * 2.1, 1.4, 9.8));
	float ignition = smoothstep(0.04, 0.19, p.y);
	float roll = noise(vec3(p.x * 6.2, p.y * 4.8 - clock * 2.6, 12.7));
	float folds = noise(vec3(p.x * 13.0 + roll * 2.2, p.y * 8.1 - clock * 4.1, 2.4));
	float filament = smoothstep(0.20, 0.80, folds);
	vec3 light = vec3(0.0);
	float transmission = 1.0;

	// Integrate emission through a small stack of turbulent flame layers.
	for (int layer = 0; layer < FLAME_LAYERS; layer++) {
		float depth = 0.60 - float(layer) * (1.20 / float(FLAME_LAYERS - 1));
		vec3 drift = vec3(p.x * 3.0, p.y * 6.1 - clock * 3.6, depth * 3.1);
		float curl = noise(drift);
		float detail = noise(drift * 2.14 + vec3(10.2, 1.7, 3.4));
		vec3 q = vec3(p.x + (curl - 0.5) * (0.13 + 0.32 * p.y),
			p.y - 0.09 + (detail - 0.5) * 0.07, depth);
		float left = tongue(q, vec2(-0.30, -0.12), left_height, 0.35, lean + 0.19);
		float center = tongue(q, vec2(0.02, 0.10), center_height, 0.43, lean - 0.09);
		float right = tongue(q, vec2(0.32, -0.09), right_height, 0.30, lean - 0.20);
		float field = max(max(left, center), right) + (roll - 0.5) * 0.15;
		float density = smoothstep(0.10, 0.80, field + (detail - 0.5) * 0.29)
			* ignition * mix(0.58, 1.12, filament);
		float heat = clamp(0.25 + 0.54 * field + 0.30 * curl + 0.24 * filament - 0.34 * p.y, 0.0, 1.0);
		float layer_alpha = 1.0 - exp(-density * (6.3 / float(FLAME_LAYERS)));
		light += transmission * layer_alpha * flame_color(heat);
		transmission *= 1.0 - layer_alpha;
	}

	float flecks = sparks(p, clock, fwidth(p.y));
	float coal_noise = noise(vec3(p.x * 49.0, p.y * 116.0, clock * 0.68));
	float bed = smoothstep(0.52, 0.87, coal_noise) * exp(-4.5 * p.x * p.x)
		* smoothstep(0.025, 0.070, p.y) * (1.0 - smoothstep(0.11, 0.19, p.y));
	float ember_alpha = max(flecks * 0.79, bed * 0.57);
	light += transmission * (flecks * vec3(2.2, 0.78, 0.10) + bed * vec3(1.36, 0.18, 0.014));
	float opacity = 1.0 - transmission * (1.0 - ember_alpha);
	if (opacity < 0.003) {
		discard;
	}
	vec3 color = light / opacity;
	// Compatibility blends in sRGB and cannot preserve HDR values in its color buffer.
	if (OUTPUT_IS_SRGB) {
		color = pow(1.0 - exp(-color), vec3(1.0 / 2.2));
	}
	ALBEDO = color;
	ALPHA = opacity;
}
