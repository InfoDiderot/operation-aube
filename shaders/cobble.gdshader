// Pavés arrondis (place) ou terre battue à ornières (routes), selon `mode`.
shader_type spatial;
#include "res://shaders/common.gdshaderinc"

uniform int mode = 0;          // 0 = pavés, 1 = chemin de terre
uniform vec4 color_a : source_color = vec4(0.42, 0.4, 0.37, 1.0);
uniform vec4 color_b : source_color = vec4(0.24, 0.22, 0.2, 1.0);
uniform float cell = 0.24;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	if (mode == 0) {
		float row = floor(p.y / cell);
		vec2 q = vec2(p.x / cell + mod(row, 2.0) * 0.5, p.y / cell);
		vec2 id = floor(q);
		vec2 f = fract(q) - 0.5;
		float h = hash12(id);
		float d = length(f * vec2(1.0, 1.15)) + h * 0.06;
		float stone = 1.0 - smoothstep(0.36, 0.46, d);
		vec3 c = color_a.rgb * (0.75 + 0.45 * h) * (0.9 + 0.2 * vnoise(p * 9.0));
		c = mix(color_b.rgb, c, stone);
		c *= 0.85 + 0.25 * fbm(p * 0.15);
		ALBEDO = c;
		ROUGHNESS = mix(0.95, 0.7, stone);
		AO = mix(0.5, 1.0, stone);
	} else {
		float n = fbm(p * 0.6);
		vec3 c = mix(color_b.rgb, color_a.rgb, n);
		// gravillons
		float grit = step(0.93, hash12(floor(p * 18.0)));
		c = mix(c, c * 1.35, grit * 0.6);
		ALBEDO = c;
		ROUGHNESS = 0.97;
	}
}
