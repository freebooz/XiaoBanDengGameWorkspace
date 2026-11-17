shader_type canvas_item;
render_mode unshaded;

uniform bool online = true;

void fragment() {
	vec4 art = texture(TEXTURE, UV) * COLOR;
	if (!online) {
		float luminance = dot(art.rgb, vec3(0.2126, 0.7152, 0.0722));
		art.rgb = vec3(luminance * 0.72);
	}
	COLOR = art;
}
