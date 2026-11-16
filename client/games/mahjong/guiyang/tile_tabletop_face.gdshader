shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D face_atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D face_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D face_orm : filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec2 atlas_origin;
uniform vec2 atlas_scale;
uniform vec4 ivory_color : source_color;
uniform float engraving_depth : hint_range(0.0, 1.0) = 0.72;

void fragment() {
	vec2 uv = atlas_origin + UV * atlas_scale;
	vec3 face = texture(face_atlas, uv, -0.36).rgb;
	// Restore contrast to ink averaged with ivory in distant mip levels.
	vec3 pigment = OUTPUT_IS_SRGB ? face : pow(face, vec3(1.0 / 2.2));
	float brightest = max(max(pigment.r, pigment.g), pigment.b);
	float darkest = min(min(pigment.r, pigment.g), pigment.b);
	float coverage = smoothstep(0.10, 0.40, max(1.0 - brightest, brightest - darkest));
	pigment *= mix(1.0, 0.68, coverage);
	face = OUTPUT_IS_SRGB ? pigment : pow(pigment, vec3(2.2));
	ALBEDO = face * ivory_color.rgb;
	NORMAL_MAP = texture(face_normal, uv).rgb;
	NORMAL_MAP_DEPTH = engraving_depth;
	vec2 orm = texture(face_orm, uv).rg;
	AO = orm.r;
	ROUGHNESS = max(orm.g, 0.44);
	SPECULAR = 0.29;
}
