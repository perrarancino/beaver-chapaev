shader_type spatial;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec2 mouth_center = vec2(1301.0, 650.0);
uniform vec2 mouth_axis = vec2(1.0, 0.0);
uniform float jaw_open : hint_range(0.0, 1.0) = 0.0;
uniform float normal_strength : hint_range(0.0, 1.0) = 1.0;

const float ATLAS_SIZE = 2048.0;

void fragment() {
	vec2 pixel = UV * ATLAS_SIZE;
	vec3 color = texture(albedo_texture, UV).rgb;
	vec3 normal = texture(normal_texture, UV).rgb;

	if (jaw_open > 0.006) {
		vec2 mouth_up = vec2(-mouth_axis.y, mouth_axis.x);
		vec2 offset = pixel - mouth_center;
		vec2 mouth = vec2(dot(offset, mouth_axis), dot(offset, mouth_up));
		float lower_depth = mix(4.0, 11.0, jaw_open);
		vec2 opening = vec2(mouth.x / mix(38.0, 41.0, jaw_open),
				(mouth.y + lower_depth - 3.0) / (lower_depth + 3.0));
		float distance_to_center = length(opening);
		float cavity = 1.0 - smoothstep(0.86, 1.02, distance_to_center);
		// The upper teeth stay at their original UVs as the lower lip opens.
		float tooth_area = (1.0 - smoothstep(23.0, 28.0, abs(mouth.x)))
				* smoothstep(-17.0, -13.0, mouth.y);
		float teeth = tooth_area * smoothstep(0.26, 0.66, min(color.r, min(color.g, color.b)));
		float inside_weight = cavity * (1.0 - teeth) * smoothstep(0.035, 0.22, jaw_open);
		float tongue = smoothstep(0.04, 0.78, -opening.y) * (1.0 - smoothstep(0.35, 0.70, abs(opening.x)));
		vec3 interior = mix(vec3(0.021, 0.005, 0.007), vec3(0.13, 0.023, 0.029), tongue * jaw_open);
		color = mix(color, interior, inside_weight);
		normal = mix(normal, vec3(0.5, 0.5, 1.0), inside_weight);
	}

	ALBEDO = color * COLOR.rgb;
	NORMAL_MAP = normal;
	NORMAL_MAP_DEPTH = normal_strength;
	ROUGHNESS = 0.85;
}
