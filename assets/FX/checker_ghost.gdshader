shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, shadows_disabled, fog_disabled;

uniform bool emblem = false;
uniform bool hostile = false;

varying vec3 local_point;

void vertex() {
	vec3 mesh_scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	local_point = VERTEX * mesh_scale;
}

void fragment() {
	float edge = pow(1.0 - clamp(dot(normalize(NORMAL), VIEW), 0.0, 1.0), 2.0);
	float mist = 0.5 + 0.5 * sin(dot(local_point, vec3(18.0, 25.0, -21.0))
		+ sin(local_point.z * 29.0 + TIME * 1.6) - TIME * 2.8);
	float veil = smoothstep(0.18, 0.88, mist);
	vec3 shadow_color = hostile ? vec3(0.46, 0.023, 0.045) : vec3(0.28, 0.22, 0.56);
	vec3 light_color = hostile ? vec3(1.0, 0.23, 0.21) : vec3(0.57, 0.78, 1.0);
	vec3 rim_color = hostile ? vec3(0.45, 0.09, 0.05) : vec3(0.25, 0.34, 0.46);
	vec3 emblem_color = hostile ? vec3(0.32, 0.14, 0.095) : vec3(0.14, 0.17, 0.24);
	vec3 shade = mix(shadow_color, light_color, veil * 0.54 + edge * 0.38);
	ALBEDO = shade + rim_color * edge * (1.55 + veil) + (emblem ? emblem_color : vec3(0.0));
	ALPHA = (emblem ? 0.56 : 0.29) + veil * 0.12 + edge * 0.19;
}
