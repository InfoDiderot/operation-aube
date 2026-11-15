// Couverture en tuiles plates ou ardoises : rangs horizontaux, recouvrement ombré, mousse.
// Les pignons (faces orientées ±Z) reçoivent la couleur du mur.
shader_type spatial;
#include "res://shaders/common.gdshaderinc"

uniform vec4 tile_color : source_color = vec4(0.47, 0.23, 0.16, 1.0);
uniform vec4 gable_color : source_color = vec4(0.74, 0.68, 0.57, 1.0);
uniform float tile_w = 0.28;
uniform float tile_h = 0.2;
uniform float moss = 0.3;

varying vec3 wpos;
varying vec3 wnorm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	if (abs(wnorm.z) > 0.9) {
		vec2 p = wpos.xy;
		ALBEDO = gable_color.rgb * (0.9 + 0.15 * fbm(p * 0.5));
		ROUGHNESS = 0.95;
	} else {
		float row = floor(wpos.y / tile_h);
		float off = mod(row, 2.0) * 0.5 * tile_w;
		float col = floor((wpos.z + off) / tile_w);
		vec2 f = vec2(fract((wpos.z + off) / tile_w), fract(wpos.y / tile_h));
		float h = hash12(vec2(col, row));
		vec3 c = tile_color.rgb * (0.82 + 0.3 * h);
		// ombre du rang supérieur et joint vertical
		c *= mix(0.55, 1.0, smoothstep(0.0, 0.35, f.y));
		c *= mix(0.7, 1.0, smoothstep(0.0, 0.06, min(f.x, 1.0 - f.x)));
		float ms = smoothstep(0.55, 0.8, fbm(wpos.zy * 0.8 + wpos.x)) * moss;
		c = mix(c, vec3(0.3, 0.36, 0.16), ms);
		ALBEDO = c;
		ROUGHNESS = 0.85;
	}
}
