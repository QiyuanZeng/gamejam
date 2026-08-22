shader_type canvas_item;
// 盖章混色：新墨盖旧墨时做乘性减色混合（Kubelka-Munk 简化），
// ink over ink 更深、red over ink 成深红——而不是普通 alpha 覆盖。

uniform sampler2D prev_tex : filter_linear;   // 上一帧画布

void fragment() {
	vec4 dst = texture(prev_tex, SCREEN_UV);
	vec4 src = COLOR;                            // 笔形顶点色
	// 减色近似：反射率相乘（白纸≈1，墨≈0.1 → ink over paper≈ink；ink over ink 更深）
	vec3 mixed_rgb = mix(dst.rgb, dst.rgb * max(src.rgb, vec3(0.02)), src.a);
	// 画布空白处直接用新墨
	float a = max(dst.a, src.a);
	COLOR = vec4(mixed_rgb, a);
}
