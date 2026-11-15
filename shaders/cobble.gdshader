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
		// Pavés carrés aux angles arrondis, rangs décalés, joints étroits et terreux
		float row = floor(p.y / cell);
		vec2 q = vec2(p.x / cell + hash12(vec2(row, 1.0)) * 0.7, p.y / cell);
		vec2 id = floor(q);
		vec2 f = fract(q) - 0.5;
		float h = hash12(id);
		vec2 a = abs(f) - (0.36 + 0.06 * h);
		float d = length(max(a, 0.0)) + min(max(a.x, a.y), 0.0);
		float stone = 1.0 - smoothstep(-0.02, 0.06, d);
		vec3 c = color_a.rgb * (0.8 + 0.35 * h) * (0.92 + 0.16 * vnoise(p * 11.0));
		c *= 1.0 - smoothstep(-0.12, 0.04, d) * 0.18;            // bombé : bords plus sombres
		vec3 joint = mix(color_b.rgb, vec3(0.3, 0.27, 0.2), 0.5);
		c = mix(joint, c, stone);
		c *= 0.85 + 0.25 * fbm(p * 0.15);
		ALBEDO = c;
		ROUGHNESS = mix(0.95, 0.75, stone);
		AO = mix(0.65, 1.0, stone);
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
