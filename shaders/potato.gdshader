// ジャガイモ用シェーダー。
// peel_mask（白＝むけた部分）を球面座標で参照し、皮と中身を塗り分ける。
// 座標の対応は scripts/potato.gd の _stamp() と必ず一致させること。
shader_type spatial;

uniform sampler2D peel_mask : filter_linear, repeat_enable;
uniform vec3 skin_color : source_color = vec3(0.56, 0.38, 0.19);
uniform vec3 flesh_color : source_color = vec3(0.93, 0.8, 0.45);
uniform float seed = 0.0;
uniform float lumpiness = 0.07;

varying vec3 local_dir;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash(i + vec3(0, 0, 0)), hash(i + vec3(1, 0, 0)), f.x),
			mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
			mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	local_dir = normalize(VERTEX);
	// でこぼこした芋らしい形にする
	float n = noise(local_dir * 2.2 + seed) * 0.7 + noise(local_dir * 5.0 + seed * 1.7) * 0.3;
	VERTEX += NORMAL * (n - 0.5) * lumpiness;
}

void fragment() {
	vec3 d = normalize(local_dir);
	vec2 uv = vec2(atan(d.x, d.z) / TAU + 0.5, acos(clamp(d.y, -1.0, 1.0)) / PI);
	float m = textureLod(peel_mask, uv, 0.0).r;

	// 皮：まだら模様と「芽」の黒い点
	float blotch = noise(d * 9.0 + seed);
	float speck = smoothstep(0.78, 0.86, noise(d * 28.0 + seed * 3.1));
	float eye = smoothstep(0.93, 0.97, noise(d * 6.0 + seed * 5.3));
	vec3 skin = skin_color * mix(0.75, 1.15, blotch);
	skin = mix(skin, skin_color * 0.45, speck * 0.6);
	skin = mix(skin, vec3(0.18, 0.12, 0.06), eye);

	// 中身：わずかな色むら
	vec3 flesh = flesh_color * mix(0.92, 1.04, noise(d * 14.0 + seed));

	float peeled = smoothstep(0.35, 0.65, m);
	// むき口の縁を少し暗くして厚みを感じさせる
	float rim = (1.0 - abs(m - 0.5) * 2.0);
	vec3 col = mix(skin, flesh, peeled);
	col *= 1.0 - rim * 0.35;

	ALBEDO = col;
	ROUGHNESS = mix(0.85, 0.35, peeled);
	SPECULAR = mix(0.3, 0.6, peeled);
	SSS_STRENGTH = peeled * 0.3;
}
