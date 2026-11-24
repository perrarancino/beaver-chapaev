shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
uniform float apothem = 2.143;
varying vec2 board_pos;
void vertex() {
	board_pos = VERTEX.xz;
}
float grain(vec2 p) {
	vec2 i = floor(p);
	vec2 f = smoothstep(vec2(0.0), vec2(1.0), fract(p));
	vec4 h = fract(sin(dot(i, vec2(127.1,311.7)) + vec4(0.,127.1,311.7,438.8)) * 4375.3);
	return mix(mix(h.x,h.y,f.x),mix(h.z,h.w,f.x),f.y);
}
void fragment() {
	vec2 p = board_pos;
	float edge = max(abs(p.x), max(abs(dot(p,vec2(0.5,0.8660254))),abs(dot(p,vec2(-0.5,0.8660254)))));
	if (edge > apothem) { discard; }
	p += vec2(UV2.y * 0.17);
	float fleck = grain(p * 89.0);
	float cloud = grain(p * 23.0);
	float s = UV.y;
	// Sample along travelled distance so bends stay fixed on the tabletop.
	float bend = (grain(vec2(s * 5.7, UV2.y)) - 0.5) * 0.94
		+ (grain(vec2(s * 15.3, UV2.y + 9.1)) - 0.5) * 0.25;
	float width = mix(0.39, 0.70, grain(vec2(s * 8.1, UV2.y + 2.7)));
	float lateral = (UV.x - bend) / width;
	float side = abs(lateral);
	float mask = (1.0 - smoothstep(0.55,1.0,side)) * (0.65 + 0.35 * cloud);
	mask *= 1.0 - smoothstep(0.91, 1.0, abs(UV.x));
	vec3 hue = vec3(0.68,0.58,0.44);
	float strength = 0.49;
	if (UV2.x == 5.0) {
		float frost = smoothstep(0.44,0.77,fleck);
		hue = mix(vec3(0.22,0.61,0.76),vec3(0.85,1.0,1.0),frost);
		strength = 0.45 + 0.46 * frost;
	} else if (UV2.x == 7.0) {
		float vein = 1.0 - smoothstep(0.06,0.24,abs(lateral - (cloud - 0.5) * 1.5));
		hue = mix(vec3(0.10,0.31,0.74),vec3(0.32,0.88,1.0),vein);
		strength = 0.44 + 0.52 * vein;
	} else if (UV2.x == 3.0) {
		float ember = smoothstep(0.43,0.72,side) * smoothstep(0.45,0.76,fleck);
		hue = mix(vec3(0.095,0.063,0.052),vec3(1.65,0.32,0.035),ember);
		strength = 0.76;
	}
	ALBEDO = hue;
	ALPHA = COLOR.a * mask * strength;
}
