shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

void fragment() {
	float density = 1.0;
	if (UV.x >= 0.0) {
		vec2 p = UV * 2.0 - 1.0;
		float angle = atan(p.y, p.x + 0.00001);
		float edge = 0.84 + 0.09 * cos(5.0 * angle + p.y);
		density = 1.0 - smoothstep(0.20, edge, length(p));
	}
	ALBEDO = COLOR.rgb;
	ALPHA = COLOR.a * density;
}
