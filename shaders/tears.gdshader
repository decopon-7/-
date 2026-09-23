// 涙で視界がにじむ画面効果。amount (0〜1) で強さを変える。
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float amount : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	float t = TIME;
	// 水の膜でゆらゆら歪む
	vec2 wobble = vec2(
		sin(uv.y * 17.0 + t * 1.9) + sin(uv.y * 41.0 - t * 2.7) * 0.4,
		cos(uv.x * 13.0 + t * 1.5) + cos(uv.x * 37.0 + t * 2.2) * 0.4) * 0.006 * amount;
	float lod = amount * 3.5;
	float blur = 0.012 * amount;
	// ぼかし（近くを数点サンプル）
	vec3 c = textureLod(screen_tex, uv + wobble, lod).rgb;
	c += textureLod(screen_tex, uv + wobble + vec2(blur, 0.0), lod).rgb;
	c += textureLod(screen_tex, uv + wobble - vec2(blur, 0.0), lod).rgb;
	c += textureLod(screen_tex, uv + wobble + vec2(0.0, blur), lod).rgb;
	c += textureLod(screen_tex, uv + wobble - vec2(0.0, blur), lod).rgb;
	c /= 5.0;
	// 周囲が暗く、少し青っぽく
	float vignette = smoothstep(0.25, 0.85, length((uv - 0.5) * vec2(1.4, 1.0)));
	c = mix(c, c * vec3(0.85, 0.9, 1.05), amount * 0.6);
	c *= 1.0 - vignette * amount * 0.7;
	COLOR = vec4(c, 1.0);
}
