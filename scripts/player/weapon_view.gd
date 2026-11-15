class_name WeaponView
extends Node3D
## Arme en vue subjective : modèles low-poly en primitives, animés par code
## (balancement, oscillation de marche, recul, rechargement, changement d'arme).

const WOOD := Color(0.42, 0.26, 0.14)
const METAL := Color(0.16, 0.16, 0.17)
const SKIN := Color(0.85, 0.66, 0.52)
const SLEEVE := Color(0.36, 0.36, 0.24)
const SWITCH_TIME := 0.45

var hip_pos := Vector3(0.2, -0.2, -0.4)
var ads_pos := Vector3(0.0, -0.05, -0.3)

var _model: Node3D
var _muzzle: Marker3D
var _flash: MeshInstance3D
var _flash_light: OmniLight3D
var _flash_t := 0.0
var _sway := Vector2.ZERO
var _kick := 0.0
var _kick_rot := 0.0
var _bob_t := 0.0
var _sprint_t := 0.0
var _reload_t := 0.0
var _reload_total := 1.0
var _switch_t := 0.0
var _throw_t := 0.0
var _interact_t := 0.0
static var _mats: Dictionary = {}


func _ready() -> void:
	_flash = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.22, 0.22)
	_flash.mesh = q
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fm.albedo_color = Color(1.0, 0.7, 0.3)
	fm.albedo_texture = _star_texture()
	_flash.material_override = fm
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flash.visible = false
	_flash_light = OmniLight3D.new()
	_flash_light.light_color = Color(1.0, 0.7, 0.35)
	_flash_light.light_energy = 2.5
	_flash_light.omni_range = 6.0
	_flash_light.visible = false


func _star_texture() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 0.0)
	t.width = 64
	t.height = 64
	return t


func set_weapon(w: WeaponData, instant := false) -> void:
	if _model:
		if _flash.get_parent() == _muzzle:
			_muzzle.remove_child(_flash)
			_muzzle.remove_child(_flash_light)
		_model.queue_free()
	_model = Node3D.new()
	add_child(_model)
	_muzzle = Marker3D.new()
	_model.add_child(_muzzle)
	match w.id:
		"garand":
			_build_garand()
		"thompson":
			_build_thompson()
		_:
			_build_pistol()
	_muzzle.add_child(_flash)
	_muzzle.add_child(_flash_light)
	_switch_t = 0.0 if instant else SWITCH_TIME
	_reload_t = 0.0
	position = hip_pos


func muzzle_position() -> Vector3:
	return _muzzle.global_position


func add_sway(rel: Vector2) -> void:
	_sway = (_sway + rel).limit_length(60.0)


func kick(w: WeaponData) -> void:
	_kick += 0.02 + w.recoil_v * 0.012
	_kick_rot += deg_to_rad(w.recoil_v * 1.6)
	_flash_t = 0.045
	_flash.rotation.z = randf() * TAU
	_flash.scale = Vector3.ONE * randf_range(0.8, 1.3)


func play_reload(duration: float) -> void:
	_reload_total = duration
	_reload_t = duration


func play_throw() -> void:
	_throw_t = 0.5


func update_view(delta: float, p: Player) -> void:
	if _model == null:
		return
	var speed := Vector2(p.velocity.x, p.velocity.z).length()
	var ads := smoothstep(0.0, 1.0, p.ads_t)
	var bob_amt := 0.0
	if p.is_on_floor() and speed > 0.5:
		_bob_t += delta * speed * (1.5 if p.sprinting else 1.9)
		bob_amt = clampf(speed / 6.0, 0.0, 1.2)
	var bob := Vector3(sin(_bob_t) * 0.012, -absf(cos(_bob_t)) * 0.014, 0.0) * bob_amt * (1.0 - ads * 0.85)
	_sway = _sway.lerp(Vector2.ZERO, 1.0 - exp(-10.0 * delta))
	var sway := Vector3(-_sway.x, _sway.y, 0.0) * 0.0004 * (1.0 - ads * 0.8)
	_kick = lerpf(_kick, 0.0, 1.0 - exp(-14.0 * delta))
	_kick_rot = lerpf(_kick_rot, 0.0, 1.0 - exp(-12.0 * delta))
	_sprint_t = move_toward(_sprint_t, 1.0 if (p.sprinting and speed > 3.0) else 0.0, delta * 5.0)
	_interact_t = move_toward(_interact_t, 1.0 if p.interact_progress > 0.0 else 0.0, delta * 5.0)

	var pos := hip_pos.lerp(ads_pos, ads) + bob + sway + Vector3(0.0, 0.0, _kick)
	var rot := Vector3(_kick_rot, -_sway.x * 0.001, 0.0)
	var sp := smoothstep(0.0, 1.0, _sprint_t)
	pos += Vector3(-0.06, -0.06, 0.05) * sp
	rot += Vector3(-0.35, 0.7, 0.25) * sp

	if _reload_t > 0.0:
		_reload_t -= delta
		var k := sin(PI * clampf(1.0 - _reload_t / _reload_total, 0.0, 1.0))
		pos += Vector3(0.0, -0.1, 0.03) * k
		rot += Vector3(-0.3, 0.0, 0.7) * k
	if _switch_t > 0.0:
		_switch_t -= delta
		var k2 := clampf(_switch_t / SWITCH_TIME, 0.0, 1.0)
		pos.y -= 0.35 * k2
		rot.x -= 0.8 * k2
	if _throw_t > 0.0:
		_throw_t -= delta
		var k3 := sin(PI * clampf(1.0 - _throw_t / 0.5, 0.0, 1.0))
		pos.y -= 0.25 * k3
		rot.x -= 0.5 * k3
	pos.y -= 0.3 * _interact_t
	position = pos
	rotation = rot

	if _flash_t > 0.0:
		_flash_t -= delta
	_flash.visible = _flash_t > 0.0
	_flash_light.visible = _flash.visible


# --- Modèles -------------------------------------------------------------------

func _mat(c: Color) -> StandardMaterial3D:
	if _mats.has(c):
		return _mats[c]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.45 if c == METAL else 0.8
	m.metallic = 0.6 if c == METAL else 0.0
	_mats[c] = m
	return m


func _box(size: Vector3, pos: Vector3, c: Color, rot_deg := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = _mat(c)
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_model.add_child(mi)
	return mi


func _cyl(radius: float, length: float, pos: Vector3, c: Color, sides := 8) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = length
	cm.radial_segments = sides
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = _mat(c)
	mi.position = pos
	mi.rotation_degrees = Vector3(90.0, 0.0, 0.0)   # axe le long de -Z
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_model.add_child(mi)
	return mi


func _hands(right: Vector3, left: Vector3) -> void:
	_box(Vector3(0.07, 0.08, 0.1), right, SKIN)
	_box(Vector3(0.075, 0.075, 0.26), right + Vector3(0.02, -0.07, 0.13), SLEEVE, Vector3(35, -8, 0))
	if left != Vector3.ZERO:
		_box(Vector3(0.08, 0.06, 0.1), left, SKIN)
		_box(Vector3(0.075, 0.075, 0.3), left + Vector3(-0.05, -0.1, 0.12), SLEEVE, Vector3(50, 30, 0))


## Hausse à cran : deux montants avec un espace au centre pour voir le guidon.
func _rear_sight(x: float, y: float, h: float, z: float) -> void:
	for side: float in [-1.0, 1.0]:
		_box(Vector3(0.006, h, 0.01), Vector3(x + side * 0.0075, y, z), METAL)
	_box(Vector3(0.022, 0.006, 0.01), Vector3(x, y - h * 0.5 + 0.003, z), METAL)


func _build_garand() -> void:
	hip_pos = Vector3(0.18, -0.2, -0.4)
	ads_pos = Vector3(0.0, -0.045, -0.3)
	_box(Vector3(0.05, 0.08, 0.5), Vector3(0, -0.035, 0.12), WOOD)          # crosse
	_box(Vector3(0.045, 0.05, 0.42), Vector3(0, -0.012, -0.32), WOOD)       # fût
	_box(Vector3(0.04, 0.045, 0.2), Vector3(0, 0.008, -0.04), METAL)        # boîte de culasse
	_cyl(0.011, 0.7, Vector3(0, 0.02, -0.52), METAL)                        # canon
	_rear_sight(0.0, 0.042, 0.03, 0.02)                                     # hausse à cran
	_box(Vector3(0.004, 0.02, 0.006), Vector3(0, 0.035, -0.84), METAL)      # guidon (sommet = ligne de mire)
	_box(Vector3(0.012, 0.035, 0.05), Vector3(0, -0.06, -0.02), METAL)      # pontet
	_hands(Vector3(0.0, -0.075, 0.03), Vector3(0.0, -0.05, -0.36))
	_muzzle.position = Vector3(0, 0.02, -0.88)


func _build_thompson() -> void:
	hip_pos = Vector3(0.18, -0.19, -0.34)
	ads_pos = Vector3(0.0, -0.045, -0.3)
	_box(Vector3(0.045, 0.09, 0.3), Vector3(0, -0.04, 0.2), WOOD)           # crosse
	_box(Vector3(0.048, 0.06, 0.3), Vector3(0, 0.0, -0.08), METAL)          # carcasse
	_cyl(0.02, 0.24, Vector3(0, 0.008, -0.34), METAL, 10)                   # canon à ailettes
	_box(Vector3(0.036, 0.09, 0.045), Vector3(0, -0.075, -0.25), WOOD, Vector3(-10, 0, 0))  # poignée avant
	_box(Vector3(0.036, 0.09, 0.045), Vector3(0, -0.07, 0.03), WOOD, Vector3(15, 0, 0))     # poignée pistolet
	_box(Vector3(0.03, 0.17, 0.045), Vector3(0, -0.1, -0.12), METAL)        # chargeur
	_rear_sight(0.0, 0.042, 0.03, 0.0)                                      # hausse à cran
	_box(Vector3(0.004, 0.022, 0.006), Vector3(0, 0.034, -0.44), METAL)     # guidon
	_hands(Vector3(0.0, -0.08, 0.04), Vector3(0.0, -0.11, -0.25))
	_muzzle.position = Vector3(0, 0.008, -0.47)


func _build_pistol() -> void:
	hip_pos = Vector3(0.16, -0.17, -0.34)
	ads_pos = Vector3(0.0, -0.043, -0.32)
	_box(Vector3(0.032, 0.035, 0.2), Vector3(0, 0.018, -0.05), METAL)       # culasse
	_box(Vector3(0.03, 0.11, 0.05), Vector3(0, -0.045, 0.03), Color(0.25, 0.18, 0.12), Vector3(15, 0, 0))
	_rear_sight(0.0, 0.039, 0.014, 0.04)                                    # hausse à cran
	_box(Vector3(0.004, 0.009, 0.006), Vector3(0, 0.0385, -0.14), METAL)    # guidon
	_hands(Vector3(0.0, -0.06, 0.05), Vector3(-0.025, -0.07, 0.04))
	_muzzle.position = Vector3(0, 0.018, -0.16)
