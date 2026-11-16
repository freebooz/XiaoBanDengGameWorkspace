shader_type spatial;
render_mode blend_add, unshaded, cull_front, depth_draw_never, shadows_disabled;

uniform vec4 glow_color : source_color = vec4(1.0, 0.69, 0.06, 1.0);
uniform float shell_width = 0.0008;
uniform float opacity = 0.8;
uniform float glow_energy = 0.65;
uniform float breath_strength = 0.06;

void vertex() {
	// The closed original tile mesh forms a bounded inverted hull. Its interior
	// is depth-occluded by the real tile, so the printed face stays readable.
	VERTEX += NORMAL * shell_width;
}

void fragment() {
	float breath = 1.0 - breath_strength + breath_strength * sin(TIME * 2.8);
	ALBEDO = glow_color.rgb;
	EMISSION = glow_color.rgb * glow_energy;
	ALPHA = opacity * breath;
}
