// 玉ねぎ（半分に切ったもの）のシェーダー。
// UV / UV2 に「切る前の位置」が入っていて、そこから層（同心円の輪）を描く。
// 外側は薄皮の表面、切り口には年輪のような層が見える。
shader_type spatial;
// 手作りメッシュ（onion.gd）は三角形ごとに向き（表裏）を計算しているが、
// 実機のGPUでバックフェースカリングにより一部が消える不具合があったため、
// 向きに関係なく常に両面を描画する。裏側は法線を反転させて正しく陰影をつける。
render_mode cull_disabled;

uniform vec3 radii = vec3(0.08, 0.07, 0.072);
uniform vec3 flesh_color : source_color = vec3(0.96, 0.95, 0.86);
uniform vec3 layer_color : source_color = vec3(0.82, 0.84, 0.62);
uniform vec3 skin_color : source_color = vec3(0.95, 0.9, 0.72);
uniform float layers = 7.0;

varying vec3 orig;

void vertex() {
	orig = vec3(UV.x, UV2.x, UV.y);
}

void fragment() {
	vec3 n = FRONT_FACING ? NORMAL : -NORMAL;
	NORMAL = n;
	vec3 q = orig / radii;
	float r = length(q);

	// 層の境目を細い線として描く
	float f = fract(r * layers);
	float boundary = 1.0 - smoothstep(0.0, 0.12, f) * smoothstep(1.0, 0.88, f);
	vec3 col = mix(flesh_color, layer_color, boundary * 0.8);
	// 中心ほどわずかに緑がかる
	col = mix(col, vec3(0.85, 0.92, 0.7), (1.0 - smoothstep(0.0, 0.35, r)) * 0.5);

	// 外側の表面：根元から先端へ走る筋
	float surface = smoothstep(0.96, 0.995, r);
	float streak = 0.5 + 0.5 * sin(atan(q.x, q.y) * 46.0);
	vec3 skin = skin_color * mix(0.9, 1.03, streak);
	col = mix(col, skin, surface);

	ALBEDO = col;
	ROUGHNESS = mix(0.18, 0.35, surface);
	SPECULAR = 0.6;
	// みずみずしさ（切り口だけ少し明るく）
	EMISSION = col * 0.04 * (1.0 - surface);
}
