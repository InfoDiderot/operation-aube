class_name Mats
extends RefCounted
## Matériaux procéduraux partagés (shaders dans res://shaders/), mis en cache par paramètres.

static var _cache: Dictionary = {}


static func _shader_mat(path: String, params: Dictionary) -> ShaderMaterial:
	var key := path + str(params)
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = load(path) as Shader
	for k: String in params:
		m.set_shader_parameter(k, params[k])
	_cache[key] = m
	return m


static func stone(color: Color, soot := 0.0) -> ShaderMaterial:
	return _shader_mat("res://shaders/stone.gdshader", {"base_color": color, "soot": soot})


static func plaster(color: Color, soot := 0.0) -> ShaderMaterial:
	return _shader_mat("res://shaders/plaster.gdshader", {"base_color": color, "soot": soot})


static func roof(tile: Color, gable: Color, slate := false) -> ShaderMaterial:
	var p := {"tile_color": tile, "gable_color": gable}
	if slate:
		p["tile_w"] = 0.34
		p["tile_h"] = 0.16
		p["moss"] = 0.12
	return _shader_mat("res://shaders/roof.gdshader", p)


static func cobble() -> ShaderMaterial:
	return _shader_mat("res://shaders/cobble.gdshader", {"mode": 0})


static func dirt_road() -> ShaderMaterial:
	return _shader_mat("res://shaders/cobble.gdshader", {"mode": 1,
		"color_a": Color(0.52, 0.44, 0.33), "color_b": Color(0.38, 0.31, 0.23)})


static func ground() -> ShaderMaterial:
	return _shader_mat("res://shaders/ground.gdshader", {})


static func foliage(tex: Texture2D, tint := Color.WHITE, sway := 0.06, sway_height := 1.0) -> ShaderMaterial:
	return _shader_mat("res://shaders/foliage.gdshader", {"albedo_tex": tex, "tint": tint,
		"sway": sway, "sway_height": sway_height})
