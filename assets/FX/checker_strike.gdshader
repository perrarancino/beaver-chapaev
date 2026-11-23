shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform sampler2D strike_atlas : source_color, filter_linear, repeat_disable;
uniform float effect_clock;

varying vec2 sprite_uv;
varying float opacity;

void vertex() {
	float elapsed = effect_clock - INSTANCE_CUSTOM.r;
	elapsed += elapsed < -4.0 ? 8.0 : 0.0;
	float age = clamp(elapsed / INSTANCE_CUSTOM.g, 0.0, 1.0);
	float tile = 2.0;
	float fade = 1.0 - smoothstep(0.06, 1.0, age);
	if (INSTANCE_CUSTOM.b < 0.5) {
		tile = mod(floor(age * 5.0), 2.0);
		fade *= 0.83 + 0.17 * cos(age * 29.0);
	} else {
		VERTEX.xz *= mix(0.70, 1.35, age);
	}
	sprite_uv = vec2((tile + UV.x) / 3.0, UV.y);
	opacity = fade;
}

void fragment() {
	vec4 sprite = texture(strike_atlas, sprite_uv);
	ALBEDO = sprite.rgb * COLOR.rgb;
	ALPHA = sprite.a * COLOR.a * opacity;
}
