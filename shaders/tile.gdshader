// 厨房の壁のタイル（サブウェイタイル）。画像は使わず、ワールド座標の X・Y から
// 互い違いに並んだ横長タイルと目地を描く。タイルごとに少しだけ色と艶を変える。
shader_type spatial;

uniform vec3 tile_color : source_color = vec3(0.86, 0.85, 0.8);
uniform vec3 grout_color : source_color = vec3(0.42, 0.4, 0.37);
uniform vec2 tile_size = vec2(0.15, 0.075);
uniform float grout = 0.0045;

varying vec3 wpos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xy / tile_size;
	float row = floor(p.y);
	p.x += mod(row, 2.0) * 0.5;  // 1段ごとに半分ずらす
	vec2 cell = floor(p);
	vec2 f = fract(p) * tile_size;
	// 目地からの距離（タイルの縁ほど少し丸く見えるよう、ふちに向かって暗くする）
	float d = min(min(f.x, tile_size.x - f.x), min(f.y, tile_size.y - f.y));
	float is_tile = smoothstep(grout * 0.5, grout, d);
	float bevel = smoothstep(grout, grout * 3.0, d);
	float n = hash(cell);
	vec3 col = tile_color * (0.93 + 0.08 * n) * mix(0.82, 1.0, bevel);
	ALBEDO = mix(grout_color, col, is_tile);
	ROUGHNESS = mix(0.85, 0.12 + 0.1 * n, is_tile);
	SPECULAR = mix(0.2, 0.6, is_tile);
}
