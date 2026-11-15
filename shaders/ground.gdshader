// Prairie : mélange de verts à plusieurs échelles, plaques d'herbe sèche et de terre.
shader_type spatial;
#include "res://shaders/common.gdshaderinc"

uniform vec4 green_a : source_color = vec4(0.27, 0.4, 0.15, 1.0);
uniform vec4 green_b : source_color = vec4(0.4, 0.5, 0.2, 1.0);
uniform vec4 dry : source_color = vec4(0.55, 0.52, 0.3, 1.0);
uniform vec4 dirt : source_color = vec4(0.36, 0.3, 0.22, 1.0);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	float big = fbm(p * 0.025);
	float mid = fbm(p * 0.15 + 3.0);
	float fine = vnoise(p * 3.0);
	vec3 c = mix(green_a.rgb, green_b.rgb, smoothstep(0.3, 0.7, big));
	c = mix(c, dry.rgb, smoothstep(0.6, 0.8, mid) * 0.6);
	c = mix(c, dirt.rgb, smoothstep(0.72, 0.85, fbm(p * 0.08 + 7.0)) * 0.7);
	c *= 0.88 + 0.22 * fine;
	ALBEDO = c;
	ROUGHNESS = 1.0;
}
