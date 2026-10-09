// 玉ねぎの入った赤いネット袋。ひし形の網目だけを残して、あいだは透かす。
shader_type spatial;
render_mode cull_disabled;

uniform vec3 net_color : source_color = vec3(0.8, 0.16, 0.08);
uniform float cells = 22.0;
uniform float thickness = 0.12;

void fragment() {
	vec2 p = UV * vec2(cells, cells * 0.6);
	float a = abs(fract(p.x + p.y) - 0.5);
	float b = abs(fract(p.x - p.y) - 0.5);
	float line = step(0.5 - thickness, max(a, b));
	if (line < 0.5) {
		discard;
	}
	ALBEDO = net_color;
	ROUGHNESS = 0.7;
}
