shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

instance uniform float hover_amount = 0.0;

varying vec2 radial;
varying float height;

void vertex() {
	radial = VERTEX.xz;
	height = VERTEX.y / 0.24 + 0.5;
	float flare = 0.93 + height * height * 0.13;
	float funnel = mix(0.42, 1.70, height * (1.36 - height * 0.36));
	float billow = 1.0 + sin(TIME * 5.7 + height * 9.0) * mix(0.033, 0.075, hover_amount);
	VERTEX.xz *= mix(flare, funnel, hover_amount) * billow;
	VERTEX.y = mix(VERTEX.y, VERTEX.y * 2.73 - 0.145, hover_amount);
}

void fragment() {
	float angle = atan(radial.y, radial.x);
	float wrap = height * mix(2.75, 4.35, hover_amount) - angle / TAU - TIME * mix(0.91, 1.45, hover_amount);
	wrap += sin(angle * 2.0 + height * 10.0 - TIME * 4.9) * mix(0.07, 0.095, hover_amount);
	float ribbon = abs(fract(wrap) - 0.5);
	float thread = 1.0 - smoothstep(0.031, 0.14, ribbon);
	float mist = 1.0 - smoothstep(0.07, 0.29, ribbon);
	float streamer = (1.0 - smoothstep(0.025, 0.094, abs(fract(wrap + 0.31) - 0.5))) * hover_amount;
	float shape = smoothstep(0.015, 0.17, height) * (1.0 - smoothstep(0.71, 1.0, height));
	float gust = smoothstep(-0.65, 0.8, sin(angle * 2.0 + TIME * 4.1 + height * 8.0));
	float taper = mix(0.45, 0.65, hover_amount) + mix(0.55, 0.35, hover_amount) * gust;
	vec3 tint = mix(vec3(0.53, 0.75, 0.82), vec3(0.24, 0.83, 0.81), hover_amount);
	ALBEDO = mix(tint, vec3(0.93, 0.99, 1.0), max(thread, streamer * 0.55));
	ALPHA = shape * taper * (thread * mix(0.41, 0.88, hover_amount) + mist * 0.12 + streamer * 0.37);
}
