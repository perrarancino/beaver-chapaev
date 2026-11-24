shader_type spatial;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float normal_strength : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	ALBEDO = texture(albedo_texture, UV).rgb * COLOR.rgb;
	NORMAL_MAP = texture(normal_texture, UV).rgb;
	NORMAL_MAP_DEPTH = normal_strength;
	ROUGHNESS = 0.85;
}
