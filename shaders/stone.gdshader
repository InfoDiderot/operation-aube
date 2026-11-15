// Mur en moellons appareillés : rangs décalés, joints creusés, salissures au pied.
shader_type spatial;
#include "res://shaders/common.gdshaderinc"

uniform vec4 base_color : source_color = vec4(0.72, 0.66, 0.55, 1.0);
uniform vec4 mortar_color : source_color = vec4(0.52, 0.49, 0.44, 1.0);
uniform float block_h = 0.3;
uniform float block_w = 0.6;
uniform float variation = 0.14;
uniform float grime = 0.45;
uniform float soot = 0.0;   // murs noircis par le feu

varying vec3 wpos;
varying vec3 wnorm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 p = face_uv(wpos, wnorm);
	float row = floor(p.y / block_h);
	float w = block_w * (0.75 + 0.6 * hash12(vec2(row, 7.0)));
	float off = hash12(vec2(row, 3.0)) * w;
	float col = floor((p.x + off) / w);
	vec2 f = vec2(fract((p.x + off) / w), fract(p.y / block_h));
	float edge = min(min(f.x, 1.0 - f.x) * w, min(f.y, 1.0 - f.y) * block_h);
	float m = smoothstep(0.008, 0.028, edge);
	float h = hash12(vec2(col, row));
	vec3 stone = base_color.rgb * (1.0 - variation + 2.0 * variation * h);
	stone *= 0.88 + 0.24 * vnoise(p * 7.0 + h * 13.0);
	vec3 c = mix(mortar_color.rgb, stone, m);
	float g = (1.0 - smoothstep(0.0, 1.4, wpos.y)) * grime;
	g += vnoise(p * 0.7) * 0.15;
	c *= 1.0 - g * 0.45;
	c = mix(c, vec3(0.06), soot * smoothstep(0.3, 0.8, fbm(p * 0.6 + 4.0)));
	ALBEDO = c;
	ROUGHNESS = 0.93;
	AO = mix(0.55, 1.0, m);
	AO_LIGHT_AFFECT = 0.4;
}
