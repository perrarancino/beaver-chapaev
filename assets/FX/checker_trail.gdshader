shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform sampler2D trail_texture : source_color, filter_linear_mipmap, repeat_disable;

void fragment() {
	// The generated stroke only occupies the central band of the source image.
	vec2 sprite_uv = vec2(mix(0.055, 0.965, UV.x), mix(0.413, 0.61, UV.y));
	float plume = texture(trail_texture, sprite_uv).a;
	ALBEDO = COLOR.rgb;
	ALPHA = plume * COLOR.a;
}
