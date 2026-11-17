shader_type spatial;
render_mode diffuse_burley;

uniform vec4 felt_color : source_color = vec4(0.12549, 0.23922, 0.14510, 1.0);
varying vec2 cloth_uv;

void vertex() {
	// Project a single cloth island across the GLB's separate bevel and cloth UV islands.
	cloth_uv = VERTEX.xz / 1.335 + vec2(0.5);
}

float fiber_density(vec2 cell) {
	vec3 key = fract(cell.xyx * vec3(0.1031, 0.1030, 0.0973));
	key += dot(key, key.yzx + 23.33);
	return fract((key.x + key.y) * key.z);
}

float felt_pile(vec2 fibers) {
	vec2 cell = floor(fibers);
	vec2 offset = fract(fibers);
	vec2 weight = offset * offset * (3.0 - 2.0 * offset);
	return mix(mix(fiber_density(cell), fiber_density(cell + vec2(1, 0)), weight.x),
		mix(fiber_density(cell + vec2(0, 1)), fiber_density(cell + vec2(1, 1)), weight.x), weight.y);
}

void fragment() {
	vec2 fibers = cloth_uv * vec2(498.0, 637.0);
	vec2 footprint = fwidth(fibers);
	float detail = 1.0 - smoothstep(0.5, 1.7, max(footprint.x, footprint.y));
	float pile = (felt_pile(fibers) - 0.5) * detail;
	vec2 from_center = abs(cloth_uv - 0.5);
	float edge = max(from_center.x, from_center.y);
	float tint = 1.0 + pile * 0.082 - 0.15 * smoothstep(0.27, 0.52, edge);
	// Matte felt gathers a soft color sheen at grazing angles.
	float facing = clamp(dot(normalize(NORMAL), VIEW), 0.0, 1.0);
	tint *= mix(0.97, 1.03, smoothstep(0.15, 0.9, cloth_uv.y)) * (1.0 + 0.10 * pow(1.0 - facing, 2.0));
	// The fiber height fades with its pixel footprint to keep distant felt stable.
	vec3 normal = normalize(NORMAL);
	vec3 surface_dx = cross(dFdy(VERTEX), normal);
	vec3 surface_dy = cross(normal, dFdx(VERTEX));
	float area = dot(dFdx(VERTEX), surface_dx);
	float fiber_height = pile * 0.00020;
	vec3 surface_gradient = (dFdx(fiber_height) * surface_dx + dFdy(fiber_height) * surface_dy) * sign(area);
	NORMAL = normalize(normal * max(abs(area), 0.00000001) - surface_gradient);
	ALBEDO = felt_color.rgb * (OUTPUT_IS_SRGB ? pow(tint, 1.0 / 2.2) : tint);
	ROUGHNESS = 0.94 + pile * 0.035;
	SPECULAR = 0.08;
	RIM = 0.18;
	RIM_TINT = 0.91;
	METALLIC = 0.0;
}
