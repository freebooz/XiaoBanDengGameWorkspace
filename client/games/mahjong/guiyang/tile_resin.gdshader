shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 ivory_color : source_color = vec4(0.906, 0.872, 0.824, 1.0);
uniform vec4 blue_color : source_color = vec4(0.0157, 0.380, 0.720, 1.0);
uniform float selection_strength = 0.0;
varying vec3 resin_position;

void vertex() {
	resin_position = VERTEX;
}

void fragment() {
	// Imported vertex R is the original layer boundary mask, independent of UV stretching.
	float back_layer = clamp(COLOR.r, 0.0, 1.0);
	// A shallow molded finish carries a soft lobe without speckling at table scale.
	float polish = sin(resin_position.x * 158.0 + 0.34 * sin(resin_position.z * 180.0));
	ALBEDO = mix(ivory_color.rgb, blue_color.rgb, back_layer);
	ALBEDO = mix(ALBEDO, vec3(0.70, 0.94, 0.16), selection_strength * 0.46);
	EMISSION = vec3(0.66, 0.94, 0.12) * selection_strength * 0.42;
	ROUGHNESS = mix(0.36, 0.295 + 0.015 * polish, back_layer);
	METALLIC = 0.0;
	SPECULAR = mix(0.38, 0.51, back_layer);
	CLEARCOAT = mix(0.18, 0.40, back_layer);
	CLEARCOAT_ROUGHNESS = 0.31;
}
