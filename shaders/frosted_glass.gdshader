// 型板ガラス（すりガラス）の窓。外の朝の光をぼんやり通し、外側の面格子が
// やわらかい影の縦じまとして透けて見える。昭和〜平成の食堂の厨房によくある窓。
// 光そのものなので、ライティングの影響を受けない（unshaded）。
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec3 sky_top : source_color = vec3(1.0, 0.96, 0.86);
uniform vec3 sky_bottom : source_color = vec3(0.86, 0.88, 0.86);
uniform float brightness = 1.25;
uniform float bar_count = 7.0;      // 面格子の縦の棒の本数
uniform float bar_shadow = 0.22;    // 棒の影の濃さ

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x),
			mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	vec3 col = mix(sky_top, sky_bottom, UV.y);
	// 面格子の縦棒（ガラス越しなのでぼやけた影になる）
	float bx = fract(UV.x * bar_count);
	float bar = 1.0 - smoothstep(0.0, 0.16, abs(bx - 0.5) - 0.02);
	// 外の植木か電線の、ぼんやりした影
	float blob = smoothstep(0.55, 0.85, noise(UV * vec2(3.0, 2.0) + vec2(4.2, 1.3)));
	// 型板ガラスの細かな凹凸
	float grain = noise(UV * vec2(160.0, 120.0)) * 0.06;
	col *= 1.0 - bar * bar_shadow - blob * 0.12;
	ALBEDO = col * brightness * (0.97 + grain);
}
