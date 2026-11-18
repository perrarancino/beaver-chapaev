shader_type spatial;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float eye_closure : hint_range(0.0, 1.0) = 0.0;
uniform float jaw_open : hint_range(0.0, 1.0) = 0.0;

const float ATLAS_SIZE = 2048.0;

void eyelid(vec2 pixel, vec2 center, vec2 axis, inout vec3 color, inout vec3 normal) {
	vec2 up = vec2(-axis.y, axis.x);
	vec2 offset = pixel - center;
	vec2 local = vec2(dot(offset, axis), dot(offset, up));
	float mask = 1.0 - smoothstep(0.76, 1.0, length(local / vec2(43.0, 32.0)));
	float edge = mix(17.0, -16.5, eye_closure) - local.x * local.x * 0.005;
	float covered = mask * smoothstep(edge - 1.3, edge + 1.0, local.y);
	float skin_height = 36.0 + max(0.0, local.y - edge) * 0.12;
	vec2 lid_uv = (center + axis * local.x + up * skin_height) / ATLAS_SIZE;
	color = mix(color, texture(albedo_texture, lid_uv).rgb * 0.91, covered);
	vec3 lid_normal = mix(texture(normal_texture, lid_uv).rgb, vec3(0.5, 0.5, 1.0), 0.7);
	normal = mix(normal, lid_normal, covered);

	float crease = 1.0 - smoothstep(0.75, 2.0, abs(local.y - edge));
	float crease_width = 1.0 - smoothstep(20.0, 29.0, abs(local.x));
	color *= 1.0 - 0.68 * crease * crease_width * eye_closure;
}

void fragment() {
	vec2 pixel = UV * ATLAS_SIZE;
	vec3 color = texture(albedo_texture, UV).rgb;
	vec3 normal = texture(normal_texture, UV).rgb;

	if (eye_closure > 0.0) {
		eyelid(pixel, vec2(1170.0, 816.0), normalize(vec2(0.78, -0.63)), color, normal);
		eyelid(pixel, vec2(1405.0, 832.0), normalize(vec2(0.65, 0.76)), color, normal);
	}

	if (jaw_open > 0.006) {
		vec2 mouth = pixel - vec2(1301.0, 650.0 - 9.0 * jaw_open);
		float opening = length(mouth / vec2(37.0 + 9.0 * jaw_open, 4.0 + 13.0 * jaw_open));
		float cavity = (1.0 - smoothstep(0.80, 1.05, opening)) * smoothstep(0.04, 0.25, jaw_open);
		vec3 inside = mix(vec3(0.028, 0.004, 0.006), vec3(0.13, 0.022, 0.026),
			smoothstep(4.0, 14.0, -mouth.y) * jaw_open);
		vec2 tooth_uv = (pixel - vec2(0.0, 6.0 * jaw_open)) / ATLAS_SIZE;
		vec3 teeth = texture(albedo_texture, tooth_uv).rgb;
		float tooth_mask = smoothstep(0.30, 0.66, min(teeth.r, min(teeth.g, teeth.b)));
		color = mix(color, mix(inside, teeth, tooth_mask), cavity);
		normal = mix(normal, vec3(0.5, 0.5, 1.0), cavity * (1.0 - tooth_mask));
	}

	ALBEDO = color;
	NORMAL_MAP = normal;
	ROUGHNESS = 0.85;
}
