shader_type canvas_item;
render_mode unshaded;

void fragment() {
	// Only the courtyard uses this pass. The transparent 3D viewport and HUD render above it.
	vec3 softened = textureLod(TEXTURE, UV, 4.0).rgb;
	float edge = smoothstep(0.3, 0.72, length(UV - vec2(0.5)));
	COLOR = vec4(mix(softened, vec3(0.0), 0.52 + edge * 0.15), 1.0);
}
