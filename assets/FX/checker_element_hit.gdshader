shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled, depth_draw_never;

// Checker.Icon values from checker.gd.
uniform int element = 7;
const int LIGHTNING = 7;
const int SNOWFLAKE = 5;

float mask(float dist, float aa) {
	return 1.0 - smoothstep(-aa, aa, dist);
}

void fragment() {
	float t = COLOR.r;
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float aa = max(fwidth(r), 0.012);
	float angle = atan(p.y, p.x + 0.00001);
	float sector = floor((angle + PI) / TAU * 9.0);
	float seed = fract(sin(sector * 53.21 + 1.3) * 4375.3);
	float axis = (sector + 0.3 + 0.4 * seed) * TAU / 9.0 - PI;
	vec2 dir = vec2(cos(axis), sin(axis));
	vec2 q = vec2(dot(p, dir), dot(p, vec2(-dir.y, dir.x)));
	float travel = 1.0 - pow(1.0 - t, 2.0);
	float front = (0.20 + 0.65 * travel) * (0.76 + 0.24 * seed);
	float fade = 1.0 - smoothstep(0.52, 1.0, t);
	vec3 rgb;
	float alpha;
	if (element == LIGHTNING) {
		float along = (q.x - front) / 0.23;
		float kink = (1.0 - abs(2.0 * fract(along + 0.25) - 1.0)) * 0.08;
		float spark = max(abs(q.y - kink) - 0.019, (abs(along) - 1.0) * 0.23);
		float flash = r - (0.28 + 0.12 * cos(angle * 6.0)) * (1.0 - t);
		float d = min(spark, flash);
		rgb = mix(vec3(0.05, 0.35, 2.1), vec3(0.55, 2.1, 3.0), mask(d, aa));
		alpha = mask(d - 0.035, aa) * fade;
	} else {
		float lobes = 0.045 * cos(6.0 * angle + 0.6 * sin(angle * 3.0));
		float smoke = mask(abs(r - (0.24 + travel * 0.43 + lobes)) - 0.13, 0.065)
			* (1.0 - smoothstep(0.36, 1.0, t)) * 0.70;
		float fire = mask(r - (0.26 + 0.23 * sin(t * PI) + lobes), 0.055)
			* (1.0 - smoothstep(0.15, 0.65, t));
		float core = mask(r - 0.21, 0.08);
		vec3 flame = mix(vec3(2.2, 0.32, 0.025), vec3(2.9, 1.95, 0.51), core);
		if (element == SNOWFLAKE) {
			flame = mix(vec3(0.34, 1.30, 1.95), vec3(1.30, 2.40, 2.90), core);
		}
		alpha = fire + smoke * (1.0 - fire);
		rgb = (flame * fire + vec3(0.29, 0.25, 0.24) * smoke * (1.0 - fire)) / max(alpha, 0.001);
	}
	ALBEDO = rgb;
	ALPHA = alpha;
}
