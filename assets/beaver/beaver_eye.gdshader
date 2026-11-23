shader_type spatial;

uniform vec3 gaze = vec3(0.0, 0.0, 1.0);
uniform float blink : hint_range(0.0, 1.0) = 0.0;
uniform vec4 iris_color : source_color = vec4(0.41, 0.20, 0.10, 1.0);
uniform sampler2D fur_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform vec2 fur_center;
uniform vec2 fur_axis;

varying vec3 eye_normal;

void vertex() {
	eye_normal = NORMAL;
}

void fragment() {
	vec3 surface = normalize(eye_normal);
	vec3 forward = normalize(gaze);
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), forward));
	vec3 up = cross(forward, right);
	vec2 iris_point = vec2(dot(surface, right), dot(surface, up));
	float iris_distance = length(iris_point);
	float iris = (1.0 - smoothstep(0.48, 0.53, iris_distance)) * step(0.0, dot(forward, surface));
	float pupil = 1.0 - smoothstep(0.29, 0.33, iris_distance);
	float rim = smoothstep(0.37, 0.50, iris_distance);
	vec3 sclera = mix(vec3(0.57, 0.45, 0.36), vec3(0.96, 0.91, 0.83),
			smoothstep(0.04, 0.67, surface.z));
	vec3 pigment = mix(iris_color.rgb, iris_color.rgb * 0.23, rim);
	pigment = mix(pigment, vec3(0.008, 0.005, 0.004), pupil);
	vec3 eye = mix(sclera, pigment, iris);

	// A small painted catchlight keeps the original eye style under dim lighting.
	float catchlight = 1.0 - smoothstep(0.075, 0.108, length(iris_point - vec2(-0.15, 0.17)));
	eye = mix(eye, vec3(1.0, 0.96, 0.89), catchlight * iris * 0.94);

	float edge = mix(1.08, -0.36, blink) - 0.32 * surface.x * surface.x;
	float lid = smoothstep(edge - 0.035, edge + 0.035, surface.y);
	lid *= smoothstep(0.0, 0.08, blink);
	lid = mix(lid, 1.0, smoothstep(0.84, 0.99, blink));
	float seam = (1.0 - smoothstep(0.022, 0.061, abs(surface.y - edge)))
			* smoothstep(0.15, 0.55, blink);
	vec2 fur_up = vec2(-fur_axis.y, fur_axis.x);
	vec2 lid_uv = fur_center + (fur_axis * surface.x * 17.0 + fur_up * surface.y * 12.0) / 2048.0;
	vec3 eyelid = texture(fur_texture, lid_uv).rgb;
	ALBEDO = mix(eye, eyelid, lid) * (1.0 - 0.43 * seam);
	ROUGHNESS = mix(0.27, 0.88, lid);
	SPECULAR = mix(0.42, 0.16, lid);
}
