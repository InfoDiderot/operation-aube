// Feuillage, herbe et fleurs : alpha découpé, double face, translucidité et vent.
// Compatible MultiMesh (MODEL_MATRIX = transformation de l'instance).
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(1.0);
uniform float alpha_cut = 0.5;
uniform float sway = 0.06;          // amplitude en mètres au sommet
uniform float sway_height = 1.0;    // hauteur (locale) où l'amplitude est maximale
uniform float wind_speed = 1.4;
uniform vec3 translucency = vec3(0.22, 0.26, 0.08);

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float k = clamp(VERTEX.y / sway_height, 0.0, 1.0);
	k *= k;
	float t = TIME * wind_speed + wp.x * 0.13 + wp.z * 0.11;
	float gust = 0.6 + 0.4 * sin(TIME * 0.35 + wp.x * 0.02);
	VERTEX.x += (sin(t) + 0.3 * sin(t * 2.7)) * sway * k * gust;
	VERTEX.z += cos(t * 0.83) * sway * 0.6 * k * gust;
}

void fragment() {
	vec4 c = texture(albedo_tex, UV);
	ALBEDO = c.rgb * tint.rgb;
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	ROUGHNESS = 0.85;
	BACKLIGHT = translucency;
}
