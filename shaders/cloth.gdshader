// 布巾（ふきん）。生成りの布に、端寄りの2本線。UV で描くので、どの箱に貼っても縞が出る。
shader_type spatial;

uniform vec3 cloth_color : source_color = vec3(0.86, 0.83, 0.74);
uniform vec3 stripe_color : source_color = vec3(0.62, 0.2, 0.17);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	float x = UV.x;
	float stripe = step(0.12, x) * step(x, 0.16) + step(0.2, x) * step(x, 0.22);
	// 織り目のざらつき
	float weave = hash(floor(UV * 420.0)) * 0.08;
	ALBEDO = mix(cloth_color, stripe_color, clamp(stripe, 0.0, 1.0)) * (0.94 + weave);
	ROUGHNESS = 0.95;
}
