shader_type spatial;
render_mode diffuse_burley;

uniform vec4 felt_color : source_color = vec4(0.13333, 0.23137, 0.16863, 1.0);
uniform sampler2D pile_map : filter_linear_mipmap_anisotropic, repeat_enable;

varying vec2 table_metres;
varying vec3 cloth_x;
varying vec3 cloth_z;

void vertex() {
	table_metres = VERTEX.xz;
	cloth_x = normalize(MODELVIEW_MATRIX[0].xyz);
	cloth_z = normalize(MODELVIEW_MATRIX[2].xyz);
}

void fragment() {
	// A short, fine nap. Mipmaps blend fibers as their spacing falls below a pixel.
	vec2 uv = table_metres / 0.18;
	vec2 drift = sin(vec2(dot(table_metres, vec2(4.1, -2.7)), dot(table_metres, vec2(2.2, 3.8))));
	vec4 pile = texture(pile_map, uv + 0.14 * drift) * 2.0 - 1.0;
	float brush = texture(pile_map, uv * 0.36 + vec2(0.37, 0.61)).a * 2.0 - 1.0;
	float angle = 0.35 + 0.72 * pile.a + 0.21 * brush;
	vec3 lay = cos(angle) * cloth_x + sin(angle) * cloth_z;
	vec3 face_normal = normalize(NORMAL);
	float grazing = 1.0 - clamp(dot(face_normal, VIEW), 0.0, 1.0);
	float value = 1.0 + 0.23 * pile.b + 0.13 * grazing * dot(lay, VIEW);
	ALBEDO = felt_color.rgb * (OUTPUT_IS_SRGB ? pow(value, 1.0 / 2.2) : value);
	// The clipped pile leans into the brush direction. Gradients average to zero in distant mips.
	NORMAL = normalize(face_normal + 0.09 * lay - 0.48 * (pile.r * cloth_x + pile.g * cloth_z));
	ROUGHNESS = 0.93 - 0.025 * pile.b;
	SPECULAR = 0.13;
	RIM = 0.21;
	RIM_TINT = 1.0;
}
