shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

instance uniform float wind_strength = 0.68;

varying vec2 radial;
varying float height;

void vertex() {
	radial = VERTEX.xz;
	height = VERTEX.y / 0.24 + 0.5;
	float flare = 0.93 + height * height * 0.13;
	float billow = 1.0 + sin(TIME * 4.4 + height * 7.0) * 0.038;
	VERTEX.xz *= flare * billow;
}

void fragment() {
	float angle = atan(radial.y, radial.x);
	float wrap = height * 2.75 - angle / TAU - TIME * 0.91;
	wrap += sin(angle * 2.0 + height * 10.0 - TIME * 4.9) * 0.07;
	float ribbon = abs(fract(wrap) - 0.5);
	float thread = 1.0 - smoothstep(0.031, 0.14, ribbon);
	float mist = 1.0 - smoothstep(0.07, 0.29, ribbon);
	float shape = smoothstep(0.015, 0.17, height) * (1.0 - smoothstep(0.71, 1.0, height));
	float taper = 0.45 + 0.55 * smoothstep(-0.65, 0.8, sin(angle * 2.0 + TIME * 4.1 + height * 8.0));
	ALBEDO = mix(vec3(0.53, 0.75, 0.82), vec3(0.93, 0.99, 1.0), thread);
	ALPHA = shape * taper * wind_strength * (thread * 0.40 + mist * 0.08);
}
