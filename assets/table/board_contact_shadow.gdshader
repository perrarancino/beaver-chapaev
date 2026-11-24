shader_type spatial;
render_mode unshaded, depth_draw_never, shadows_disabled, fog_disabled;

varying vec2 board_position;

void vertex() {
	board_position = VERTEX.xz;
}

void fragment() {
	vec2 point = abs(board_position);
	float edge_distance = max(point.x, 0.5 * point.x + 0.8660254 * point.y) - 2.152;
	ALBEDO = vec3(0.045, 0.030, 0.022);
	ALPHA = 0.72 * (1.0 - smoothstep(0.005, 0.169, edge_distance));
}
