shader_type spatial;

#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
// Avoid stair-stepped self-shadowing across the overlapping fur meshes.
render_mode shadows_disabled;
#endif

uniform vec4 base : source_color = vec4(0.42, 0.24, 0.14, 1.0);
uniform bool tail_scales = false;
varying vec3 model_point;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.13, 0.27, 0.49));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float grain(vec3 p) {
	vec3 cell = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash(cell), hash(cell + vec3(1, 0, 0)), f.x),
			mix(hash(cell + vec3(0, 1, 0)), hash(cell + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(cell + vec3(0, 0, 1)), hash(cell + vec3(1, 0, 1)), f.x),
			mix(hash(cell + vec3(0, 1, 1)), hash(cell + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	model_point = VERTEX;
}

void fragment() {
	float coat = grain(model_point * vec3(15.0, 6.0, 15.0));
	vec3 strands = model_point * vec3(140.0, 26.0, 140.0) + coat;
	float footprint = max(length(dFdx(strands)), length(dFdy(strands)));
	float detail = mix(grain(strands), 0.5, smoothstep(0.65, 2.0, footprint));
	ALBEDO = base.rgb * (0.72 + 0.40 * coat + 0.21 * detail);
	ROUGHNESS = 0.82 + detail * 0.13;
	if (tail_scales) {
		vec2 p = model_point.xz * vec2(9.0, 13.0);
		vec2 diamonds = vec2(p.x + p.y, p.x - p.y);
		vec2 edge = abs(fract(diamonds) - 0.5);
		float seam = smoothstep(0.37, 0.49, max(edge.x, edge.y));
		ALBEDO *= 1.0 - 0.38 * seam;
		ROUGHNESS = 0.65 + 0.25 * seam;
	}
}
