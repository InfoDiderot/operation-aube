// Ciel d'aube : dégradé chaud à l'horizon, disque solaire et halo, nuages fbm statiques.
shader_type sky;
#include "res://shaders/common.gdshaderinc"

uniform vec3 top_color : source_color = vec3(0.26, 0.38, 0.6);
uniform vec3 horizon_color : source_color = vec3(0.96, 0.7, 0.5);
uniform vec3 ground_color : source_color = vec3(0.33, 0.31, 0.28);
uniform float cloud_cover = 0.55;
uniform float cloud_scale = 1.6;

void sky() {
	vec3 d = EYEDIR;
	float h = d.y;
	vec3 col = mix(horizon_color, top_color, smoothstep(-0.02, 0.45, h));
	vec3 sd = LIGHT0_DIRECTION;
	float sdot = max(dot(d, sd), 0.0);
	// halo chaud autour du soleil, plus large près de l'horizon
	col += vec3(1.0, 0.65, 0.35) * pow(sdot, 6.0) * 0.45;
	if (h > 0.0) {
		vec2 uv = d.xz / (h + 0.12) * cloud_scale;
		float c = fbm(uv * 0.6) * 0.65 + fbm(uv * 2.1 + 5.0) * 0.35;
		c = smoothstep(1.0 - cloud_cover, 1.05 - cloud_cover * 0.4, c);
		vec3 lit = mix(vec3(1.0, 0.86, 0.74), vec3(1.0, 0.7, 0.5), pow(sdot, 3.0));
		vec3 shade = mix(horizon_color, top_color, 0.5) * 0.75;
		vec3 cc = mix(shade, lit, 0.45 + 0.55 * fbm(uv * 1.3 + 2.0));
		col = mix(col, cc, c * smoothstep(0.0, 0.12, h) * 0.9);
	}
	// disque solaire (masqué par les nuages ci-dessus seulement en partie)
	col += LIGHT0_COLOR * LIGHT0_ENERGY * smoothstep(0.9995, 0.9998, dot(d, sd)) * 3.0;
	col = mix(col, ground_color, smoothstep(0.0, -0.08, h));
	COLOR = col;
}
