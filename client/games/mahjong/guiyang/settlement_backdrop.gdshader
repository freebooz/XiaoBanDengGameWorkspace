shader_type canvas_item;
render_mode unshaded;
uniform sampler2D board : hint_screen_texture, repeat_disable, filter_linear_mipmap;

void fragment() {
	vec3 table = textureLod(board, SCREEN_UV, 2.2).rgb;
	COLOR = vec4(mix(table, vec3(0.010, 0.065, 0.040), 0.60), 1.0);
}
