shader_type canvas_item;

uniform float sheen_pos : hint_range(-0.5, 1.5) = -0.5;
uniform float sheen_strength : hint_range(0.0, 0.5) = 0.0;
uniform float brightness_boost : hint_range(0.0, 0.25) = 0.0;

void fragment() {
	vec4 base = texture(TEXTURE, UV) * COLOR;
	if (base.a > 0.01) {
		float diag = UV.x * 0.72 + UV.y * 0.28;
		float band = smoothstep(0.18, 0.0, abs(diag - sheen_pos));
		vec3 gold_tint = vec3(1.0, 0.94, 0.74);
		base.rgb += gold_tint * band * sheen_strength * base.a;
		base.rgb += vec3(brightness_boost) * base.a;
	}
	COLOR = base;
}
