// Enduit à la chaux : taches douces, éclats, salissures au pied et coulures.
shader_type spatial;
#include "res://shaders/common.gdshaderinc"

uniform vec4 base_color : source_color = vec4(0.86, 0.8, 0.68, 1.0);
uniform float grime = 0.5;
uniform float soot = 0.0;

varying vec3 wpos;
varying vec3 wnorm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 p = face_uv(wpos, wnorm);
	float stains = fbm(p * 0.45);
	vec3 c = base_color.rgb * (0.88 + 0.2 * stains);
	c *= 0.96 + 0.06 * vnoise(p * 25.0);
	// éclats d'enduit laissant voir la pierre
	float chip = smoothstep(0.72, 0.76, fbm(p * 1.3 + 11.0));
	c = mix(c, vec3(0.58, 0.53, 0.45), chip * 0.85);
	// coulures verticales
	float streak = vnoise(vec2(p.x * 6.0, p.y * 0.4)) * smoothstep(5.0, 1.0, wpos.y);
	c *= 1.0 - streak * 0.12;
	float g = (1.0 - smoothstep(0.0, 1.0, wpos.y)) * grime;
	c *= 1.0 - g * 0.4;
	c = mix(c, vec3(0.07), soot * smoothstep(0.35, 0.8, fbm(p * 0.5 + 2.0)));
	ALBEDO = c;
	ROUGHNESS = 0.95;
}
