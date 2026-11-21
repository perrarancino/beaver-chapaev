shader_type spatial;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec2 left_eye_center = vec2(1170.0, 816.0);
uniform vec2 right_eye_center = vec2(1405.0, 832.0);
uniform vec2 left_eye_axis = vec2(0.78, -0.63);
uniform vec2 right_eye_axis = vec2(0.65, 0.76);
uniform vec2 mouth_center = vec2(1301.0, 650.0);
uniform vec2 mouth_axis = vec2(1.0, 0.0);
uniform float eye_closure : hint_range(0.0, 1.0) = 0.0;
uniform float jaw_open : hint_range(0.0, 1.0) = 0.0;
uniform float normal_strength : hint_range(0.0, 1.0) = 1.0;

const float ATLAS_SIZE = 2048.0;

void eyelid(vec2 pixel, vec2 center, vec2 axis, vec2 uv_dx, vec2 uv_dy,
		inout vec3 color, inout vec3 normal) {
	vec2 up = vec2(-axis.y, axis.x);
	vec2 offset = pixel - center;
	vec2 local = vec2(dot(offset, axis), dot(offset, up));
	float mask = 1.0 - smoothstep(0.76, 1.0, length(local / vec2(43.0, 32.0)));
	if (mask <= 0.0) {
		return;
	}
	float edge = mix(35.0, -16.5, eye_closure) - local.x * local.x * 0.005;
	float sweep = smoothstep(edge - 1.3, edge + 1.0, local.y);
	float seal = smoothstep(0.82, 1.0, eye_closure);
	float covered = mask * mix(sweep, 1.0, seal);
	if (covered > 0.0) {
		// The blink moves the coverage edge, while the eyelid texture stays in the same UVs.
		float skin_height = 36.0 + (local.y + 32.0) * 0.12;
		vec2 lid_uv = (center + axis * local.x + up * skin_height) / ATLAS_SIZE;
		color = mix(color, textureGrad(albedo_texture, lid_uv, uv_dx, uv_dy).rgb * 0.91, covered);
		normal = mix(normal, vec3(0.5, 0.5, 1.0), covered);
	}

	float crease = 1.0 - smoothstep(0.75, 2.0, abs(local.y - edge));
	float crease_width = 1.0 - smoothstep(20.0, 29.0, abs(local.x));
	color *= 1.0 - 0.68 * crease * crease_width * eye_closure * mask;
}

void fragment() {
	vec2 pixel = UV * ATLAS_SIZE;
	// Use the mesh UV footprint for animated atlas overlays, even across their masked edges.
	vec2 uv_dx = dFdx(UV);
	vec2 uv_dy = dFdy(UV);
	vec3 color = texture(albedo_texture, UV).rgb;
	vec3 normal = texture(normal_texture, UV).rgb;

	if (eye_closure > 0.0) {
		eyelid(pixel, left_eye_center, normalize(left_eye_axis), uv_dx, uv_dy, color, normal);
		eyelid(pixel, right_eye_center, normalize(right_eye_axis), uv_dx, uv_dy, color, normal);
	}

	if (jaw_open > 0.006) {
		vec2 mouth_up = vec2(-mouth_axis.y, mouth_axis.x);
		vec2 offset = pixel - mouth_center;
		vec2 mouth = vec2(dot(offset, mouth_axis), dot(offset, mouth_up) + 9.0 * jaw_open);
		float opening = length(mouth / vec2(37.0 + 9.0 * jaw_open, 4.0 + 13.0 * jaw_open));
		float cavity = (1.0 - smoothstep(0.80, 1.05, opening)) * smoothstep(0.04, 0.25, jaw_open);
		if (cavity > 0.0) {
			vec3 inside = mix(vec3(0.028, 0.004, 0.006), vec3(0.13, 0.022, 0.026),
				smoothstep(4.0, 14.0, -mouth.y) * jaw_open);
			vec2 tooth_uv = (pixel - mouth_up * 6.0 * jaw_open) / ATLAS_SIZE;
			vec3 teeth = textureGrad(albedo_texture, tooth_uv, uv_dx, uv_dy).rgb;
			float tooth_mask = smoothstep(0.30, 0.66, min(teeth.r, min(teeth.g, teeth.b)));
			color = mix(color, mix(inside, teeth, tooth_mask), cavity);
			normal = mix(normal, vec3(0.5, 0.5, 1.0), cavity * (1.0 - tooth_mask));
		}
	}

	ALBEDO = color;
	NORMAL_MAP = normal;
	NORMAL_MAP_DEPTH = normal_strength;
	ROUGHNESS = 0.85;
}
