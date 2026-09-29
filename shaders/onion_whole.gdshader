// ケースに積まれた「切る前」の玉ねぎ（丸ごと）用のシェーダー。
// 標準の SphereMesh の UV（経度・緯度）をそのまま使い、縦の薄皮の筋と、
// 上下の枯れた根っこ・芽の跡を描く。玉ねぎごとに seed / base_color を変えて
// 見た目にばらつきを出す（main.gd 側で1個ずつ別のマテリアルを渡す）。
shader_type spatial;

uniform vec3 base_color : source_color = vec3(0.82, 0.55, 0.25);
uniform vec3 dark_color : source_color = vec3(0.45, 0.24, 0.1);
uniform float seed = 0.0;
uniform float streak_count = 16.0;

void fragment() {
	// 経度方向に走る、薄皮の重なりを思わせる縦筋
	float streak = 0.5 + 0.5 * sin((UV.x + seed) * streak_count * TAU);
	vec3 col = mix(dark_color, base_color, 0.4 + 0.5 * streak);

	// 根元（緯度1.0側）の、枯れた根っこの跡
	float root = smoothstep(0.82, 0.99, UV.y);
	col = mix(col, dark_color * 0.55, root);

	// 芽（緯度0.0側）の、切り落とした跡
	float stem = smoothstep(0.88, 1.0, 1.0 - UV.y);
	col = mix(col, dark_color * 0.75, stem * 0.7);

	ALBEDO = col;
	ROUGHNESS = 0.55;
	SPECULAR = 0.25;
}
