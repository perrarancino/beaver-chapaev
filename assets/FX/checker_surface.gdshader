shader_type spatial;

uniform sampler2D wood_texture : source_color, hint_default_white, filter_linear_mipmap_anisotropic;
uniform sampler2D surface_normal : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D arc_atlas : source_color, filter_linear, repeat_disable;
uniform vec4 base_color : source_color = vec4(1.0);
uniform float base_roughness = 0.55;
uniform float metal = 0.0;
uniform bool has_normal = false;
uniform bool icy = false;
uniform bool electric = false;
instance uniform bool is_rim = false;
instance uniform vec3 part_offset = vec3(0.0);

varying vec3 surface_point;

void vertex() {
	vec3 mesh_scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	vec3 point = VERTEX * mesh_scale;
	surface_point = (is_rim ? vec3(point.x, point.z, -point.y) : point) + part_offset;
}

float hash(vec2 cell) {
	vec3 p = fract(vec3(cell.xyx) * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float noise(vec2 point) {
	vec2 cell = floor(point);
	vec2 weight = fract(point);
	weight = weight * weight * (3.0 - 2.0 * weight);
	return mix(
		mix(hash(cell), hash(cell + vec2(1.0, 0.0)), weight.x),
		mix(hash(cell + vec2(0.0, 1.0)), hash(cell + vec2(1.0)), weight.x),
		weight.y);
}

vec2 ice_facets(vec2 point) {
	vec2 origin = floor(point - 0.5) + 0.5;
	float near_cell = 10.0;
	float next_cell = 10.0;
	float shade = 0.0;
	for (int y = 0; y < 2; y++) {
		for (int x = 0; x < 2; x++) {
			vec2 cell = origin + vec2(float(x), float(y));
			float id = hash(cell);
			vec2 seed = cell + (vec2(id, hash(cell + vec2(17.3, 31.4))) - 0.5) * 0.46;
			vec2 offset = point - seed;
			float distance_to_cell = dot(offset, offset);
			if (distance_to_cell < near_cell) {
				next_cell = near_cell;
				near_cell = distance_to_cell;
				shade = id;
			} else {
				next_cell = min(next_cell, distance_to_cell);
			}
		}
	}
	return vec2(next_cell - near_cell, shade);
}

void fragment() {
	vec3 wood = base_color.rgb;
	if (!icy) {
		wood *= texture(wood_texture, UV).rgb;
	}
	vec3 p = surface_point;
	vec2 grain = p.xz + p.y * vec2(0.81, 0.67);
	float edge = smoothstep(0.060, 0.151, length(p.xz));
	METALLIC = metal;
	if (has_normal) {
		NORMAL_MAP = texture(surface_normal, UV).rgb;
	}
	if (electric) {
		float radius = length(p.xz);
		float sector = atan(p.z, p.x + 0.000001) * (5.0 / TAU) + 0.22;
		float arc_frame = mod(floor(TIME * 9.0) + floor(sector), 2.0);
		// Run the same bolt out across the face, then down around the edge.
		float run = clamp((radius - 0.062) * 5.8, 0.0, 0.56)
			+ clamp((0.047 - p.y) * 4.2, 0.0, 0.42);
		vec4 arc = texture(arc_atlas, vec2((arc_frame + run) / 3.0, fract(sector)));
		float charge = 0.79 + 0.21 * sin(TIME * 4.2 - run * 11.0 + floor(sector) * 1.8);
		float energy = arc.a * smoothstep(0.059, 0.097, radius) * charge;
		vec3 blue_wood = mix(wood * vec3(0.55, 0.70, 0.91), vec3(0.030, 0.086, 0.16), 0.42);
		ALBEDO = mix(blue_wood, arc.rgb * vec3(0.55, 0.80, 1.0), energy * 0.52);
		ROUGHNESS = mix(base_roughness, 0.37, energy);
		EMISSION = arc.rgb * vec3(0.58, 0.87, 1.16) * (energy * 0.42 + energy * energy * 1.35);
	} else if (icy) {
		vec2 grid = mat2(vec2(24.0, -13.0), vec2(11.0, 33.0)) * grain;
		vec2 facets = ice_facets(grid);
		float detail = 1.0 - smoothstep(0.30, 0.85, length(fwidth(grid)));
		float cracks = (1.0 - smoothstep(0.018, 0.17, facets.x)) * detail;
		float clusters = noise(grain * 25.0);
		float frost = smoothstep(0.22, 0.74, clusters * 0.62 + edge * 0.45);
		float glint = pow(max(0.0, sin(dot(p, vec3(14.0, 7.0, 20.0)) - TIME * 1.35)), 14.0);
		vec3 glass = mix(vec3(0.10, 0.36, 0.55), vec3(0.58, 0.84, 0.97), facets.y);
		vec3 rime = mix(glass, vec3(0.76, 0.91, 1.0), frost * 0.71 + cracks * 0.20);
		float brightness = dot(base_color.rgb, vec3(0.21, 0.72, 0.07));
		vec3 ice_base = mix(vec3(0.065, 0.15, 0.25), vec3(0.26, 0.48, 0.61), brightness);
		ALBEDO = mix(ice_base, rime, 0.66 + frost * 0.30);
		ROUGHNESS = mix(0.24, 0.55, frost);
		EMISSION = vec3(0.33, 0.68, 0.95) * (0.02 + frost * 0.04 + cracks * (0.15 + glint * 0.26));
	} else {
		float time = TIME * 0.9;
		vec2 flame = grain * vec2(20.0, 15.0) + vec2(time * 0.13, -time);
		float rolling = noise(flame);
		float tongues = noise(flame * 2.1 + vec2(rolling * 1.5, -time * 0.65));
		float flow = rolling * 0.64 + tongues * 0.36;
		float heat = smoothstep(0.40, 0.85, flow + edge * 0.13);
		float seams = (1.0 - smoothstep(0.016, 0.105, abs(flow - 0.58))) * heat;
		vec3 ember = mix(vec3(0.47, 0.027, 0.006), vec3(1.0, 0.35, 0.035), heat);
		ALBEDO = mix(wood * vec3(0.62, 0.37, 0.27), ember, heat * 0.76);
		ROUGHNESS = mix(base_roughness, 0.38, heat);
		EMISSION = ember * heat * 0.42 + vec3(1.0, 0.44, 0.10) * seams * 0.52;
	}
}
