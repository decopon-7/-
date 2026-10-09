// 木目のシェーダー（まな板・玉ねぎのケース用）。画像は使わず、ワールド座標から木目を描く。
// 板の長手方向（X）に年輪の筋が走り、板ごとに少しずつずれる。
shader_type spatial;

uniform vec3 base_color : source_color = vec3(0.82, 0.62, 0.38);
uniform vec3 dark_color : source_color = vec3(0.58, 0.39, 0.2);
uniform float grain_scale = 340.0;
uniform float seed = 0.0;
uniform float roughness_value = 0.78;

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
	// 筋はX方向に長く、Z方向に細かく並ぶ。ゆるい波で曲げて、木目らしいうねりを出す
	// うねり（板全体でゆるく曲がる）と、細い年輪の線、さらに細かい繊維のざらつきを重ねる
	float warp = noise(vec2(wpos.x * 4.0 + seed, wpos.z * 7.0)) * 5.0;
	float rings = abs(sin(wpos.z * grain_scale + warp * 3.0 + seed * 10.0));
	float ring_line = smoothstep(0.55, 1.0, rings);
	float fiber = noise(vec2(wpos.x * 14.0, wpos.z * 900.0 + seed));
	float t = clamp(ring_line * 0.7 + fiber * 0.3, 0.0, 1.0);
	vec3 col = mix(base_color, dark_color, t * 0.85);
	// 板ごとの色むら（ごくゆるく）
	col *= 0.95 + 0.08 * noise(vec2(wpos.x * 2.0, wpos.z * 3.0 + seed));
	ALBEDO = col;
	ROUGHNESS = roughness_value;
}
