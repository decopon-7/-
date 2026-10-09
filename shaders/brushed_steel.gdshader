// 作業台の天板などの、ヘアライン仕上げのステンレス。ワールド座標の X 方向に細い筋が走り、
// ところどころに使い込んだ細かい傷とくもりがある。
shader_type spatial;

uniform vec3 base_color : source_color = vec3(0.62, 0.63, 0.64);
uniform float metal = 0.75;

varying vec3 wpos;

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

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// 横方向に長く伸びた細かいノイズ＝ヘアライン
	float hair = noise(vec2(wpos.x * 6.0, wpos.z * 1400.0)) * 0.6 + noise(vec2(wpos.x * 2.0, wpos.z * 380.0)) * 0.4;
	// ゆるいくもり（拭き跡）
	float smudge = noise(wpos.xz * 7.0);
	vec3 col = base_color * (0.9 + 0.12 * hair) * (0.94 + 0.08 * smudge);
	ALBEDO = col;
	METALLIC = metal;
	ROUGHNESS = 0.3 + 0.18 * hair + 0.1 * smudge;
}
