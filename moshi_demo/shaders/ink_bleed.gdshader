shader_type canvas_item;
// 渗墨反馈：每帧对上一帧画布做 5-tap 模糊并乘消褪系数。
// 逐帧迭代 ≈ 扩散方程，墨迹在纸上缓慢晕开。

uniform sampler2D src_tex : filter_linear;
uniform float blur_radius = 1.2;   // 渗墨速度
uniform float fade = 0.992;        // 消褪

void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE * blur_radius;
	vec4 c = texture(src_tex, SCREEN_UV) * 0.4;
	c += texture(src_tex, SCREEN_UV + vec2(px.x, 0.0)) * 0.15;
	c += texture(src_tex, SCREEN_UV - vec2(px.x, 0.0)) * 0.15;
	c += texture(src_tex, SCREEN_UV + vec2(0.0, px.y)) * 0.15;
	c += texture(src_tex, SCREEN_UV - vec2(0.0, px.y)) * 0.15;
	// 消褪只作用在已有墨迹上（透明区不衰减出灰底）
	c.a *= fade;
	COLOR = c;
}
