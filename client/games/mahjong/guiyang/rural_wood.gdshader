shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D wood_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec4 wood_color : source_color = vec4(1.0);
varying vec3 grain_position;
varying vec3 grain_normal;

void vertex() {
	grain_position = VERTEX;
	grain_normal = NORMAL;
}

void fragment() {
	vec3 p = grain_position;
	vec3 blend = pow(abs(normalize(grain_normal)), vec3(5.0));
	blend /= max(blend.x + blend.y + blend.z, 0.001);
	float rail = smoothstep(-0.051, 0.051, abs(p.x) - abs(p.z));
	// Each rail's top and skirt use the same along-rail UV through the bevel.
	vec2 front_uv = vec2(p.x * 0.58 + 0.5, 0.5 + (abs(p.z) - 0.69 - p.y) * 2.25);
	vec2 side_uv = vec2(p.z * 0.58 + 0.5, 0.5 + (abs(p.x) - 0.69 - p.y) * 2.25);
	float side_weight = blend.x + blend.y * rail;
	vec3 grain = mix(texture(wood_albedo, front_uv).rgb, texture(wood_albedo, side_uv).rgb, side_weight);
	vec3 linear_grain = OUTPUT_IS_SRGB ? pow(grain, vec3(2.2)) : grain;
	float grain_luminance = dot(linear_grain, vec3(0.2126, 0.7152, 0.0722));
	// The solid skirt reads a little darker beneath the shaped top shoulder.
	float shoulder = smoothstep(-0.042, 0.009, p.y);
	float apron = mix(0.65, 1.08, shoulder);
	ALBEDO = grain * wood_color.rgb * (OUTPUT_IS_SRGB ? pow(apron, 1.0 / 2.2) : apron);
	vec3 normal = normalize(NORMAL);
	vec3 surface_dx = cross(dFdy(VERTEX), normal);
	vec3 surface_dy = cross(normal, dFdx(VERTEX));
	float area = dot(dFdx(VERTEX), surface_dx);
	float fiber_height = grain_luminance * 0.00010;
	vec3 grain_relief = (dFdx(fiber_height) * surface_dx + dFdy(fiber_height) * surface_dy) * sign(area);
	NORMAL = normalize(normal * max(abs(area), 0.00000001) - grain_relief);
	ROUGHNESS = mix(0.49, 0.32, shoulder) + mix(0.030, -0.022, smoothstep(0.09, 0.43, grain_luminance));
	SPECULAR = 0.42;
	METALLIC = 0.0;
	CLEARCOAT = mix(0.17, 0.47, shoulder);
	CLEARCOAT_ROUGHNESS = 0.34;
}
