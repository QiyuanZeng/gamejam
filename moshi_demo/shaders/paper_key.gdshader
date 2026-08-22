shader_type canvas_item;

// 宣纸亮度键控：AI 图自带的亮纸底 → 透明，深墨实体保留（灰晕自然过渡）
uniform float threshold : hint_range(0.0, 1.0) = 0.55;
uniform float softness : hint_range(0.0, 0.2) = 0.08;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float lum = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	float a = c.a * (1.0 - smoothstep(threshold, threshold + softness, lum));
	COLOR = vec4(c.rgb, a);
}
