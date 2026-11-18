shader_type canvas_item;
render_mode unshaded;

void fragment() {
	float radius = length(UV - vec2(0.5));
	float aa = max(fwidth(radius), 0.001);
	vec3 portrait = texture(TEXTURE, clamp((UV - vec2(0.5)) * 1.06 + vec2(0.5), 0.0, 1.0)).rgb;
	vec3 rim = mix(vec3(0.54, 0.24, 0.04), vec3(1.0, 0.83, 0.39), smoothstep(0.458, 0.481, radius));
	portrait = mix(portrait, rim, smoothstep(0.458 - aa, 0.458, radius));
	portrait = mix(portrait, vec3(0.65, 0.34, 0.10), smoothstep(0.487, 0.497, radius));
	COLOR = vec4(portrait, 1.0 - smoothstep(0.5 - aa, 0.5, radius));
}
