shader_type canvas_item;
// 渗墨画布合成：墨迹纹理 × 纸颗粒（颗粒处墨迹略浅 = 纸纹吃墨）。

uniform sampler2D grain_tex : filter_linear, repeat_enable;
uniform float grain_strength = 0.35;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float g = texture(grain_tex, UV * 3.0).r;
	c.a *= 1.0 - grain_strength * 0.5 * (1.0 - g);
	COLOR = c;
}
