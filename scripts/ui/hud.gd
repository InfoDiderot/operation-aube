class_name Hud
extends CanvasLayer
## Interface en jeu : réticule dynamique, marqueur d'impact, indicateurs de dégâts,
## objectif + marqueur 3D, munitions, santé, invite d'interaction, bannières, compte à rebours.

const VIGNETTE_SHADER := """
shader_type canvas_item;
uniform float hurt = 0.0;
uniform float base = 0.35;
void fragment() {
	vec2 uv = UV - 0.5;
	float d = length(uv * vec2(1.0, 0.85));
	float dark = smoothstep(0.35, 0.85, d) * base;
	float red = smoothstep(0.2, 0.75, d) * hurt;
	COLOR = vec4(mix(vec3(0.0), vec3(0.55, 0.0, 0.0), red / max(red + dark, 0.001)), clamp(dark + red, 0.0, 0.9));
}
"""

var player: Player

var _overlay: Control
var _vignette: ColorRect
var _vig_mat: ShaderMaterial
var _obj_label: Label
var _counter_label: Label
var _ammo_label: Label
var _weapon_label: Label
var _gren_label: Label
var _health_bar: ProgressBar
var _prompt_label: Label
var _prompt_bar: ProgressBar
var _banner_title: Label
var _banner_sub: Label
var _flash_label: Label
var _timer_label: Label
var _hint_label: Label

var objective_pos: Variant = null
var _hit_t := 0.0
var _hit_kill := false
var _hurt_pulse := 0.0
var _damage_dirs: Array[Dictionary] = []
var _banner_t := 0.0
var _flash_t := 0.0
var _hint_t := 14.0


class Overlay extends Control:
	var hud: Hud
	func _draw() -> void:
		hud._draw_overlay(self)


func _ready() -> void:
	layer = 5
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_vignette = ColorRect.new()
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = VIGNETTE_SHADER
	_vig_mat = ShaderMaterial.new()
	_vig_mat.shader = sh
	_vignette.material = _vig_mat
	root.add_child(_vignette)

	var ov := Overlay.new()
	ov.hud = self
	ov.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(ov)
	_overlay = ov

	# Objectif (haut gauche)
	var obj_box := VBoxContainer.new()
	obj_box.position = Vector2(32, 28)
	obj_box.custom_minimum_size = Vector2(560, 0)
	root.add_child(obj_box)
	var obj_title := _label("OBJECTIF", 15, Color(0.95, 0.8, 0.45))
	obj_box.add_child(obj_title)
	_obj_label = _label("", 22, Color(1, 1, 1))
	_obj_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_obj_label.custom_minimum_size = Vector2(560, 0)
	obj_box.add_child(_obj_label)
	_counter_label = _label("", 17, Color(0.85, 0.85, 0.8))
	obj_box.add_child(_counter_label)

	# Munitions (bas droite)
	var ammo_box := VBoxContainer.new()
	ammo_box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	ammo_box.offset_left = -320
	ammo_box.offset_top = -130
	ammo_box.offset_right = -32
	ammo_box.offset_bottom = -24
	ammo_box.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(ammo_box)
	_weapon_label = _label("", 18, Color(0.9, 0.88, 0.8))
	_weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ammo_box.add_child(_weapon_label)
	_ammo_label = _label("", 40, Color(1, 1, 1))
	_ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ammo_box.add_child(_ammo_label)
	_gren_label = _label("", 17, Color(0.85, 0.85, 0.75))
	_gren_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ammo_box.add_child(_gren_label)

	# Santé (bas gauche)
	var hb := VBoxContainer.new()
	hb.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	hb.offset_left = 32
	hb.offset_top = -70
	hb.offset_right = 300
	hb.offset_bottom = -28
	root.add_child(hb)
	hb.add_child(_label("SANTÉ", 14, Color(0.9, 0.85, 0.7)))
	_health_bar = ProgressBar.new()
	_health_bar.custom_minimum_size = Vector2(260, 12)
	_health_bar.show_percentage = false
	_health_bar.max_value = Player.MAX_HEALTH
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.5)
	var fg := StyleBoxFlat.new()
	fg.bg_color = Color(0.85, 0.82, 0.7)
	_health_bar.add_theme_stylebox_override("background", bg)
	_health_bar.add_theme_stylebox_override("fill", fg)
	hb.add_child(_health_bar)

	# Invite d'interaction (centre bas)
	var pbox := VBoxContainer.new()
	pbox.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	pbox.offset_left = -220
	pbox.offset_right = 220
	pbox.offset_top = 90
	pbox.offset_bottom = 160
	root.add_child(pbox)
	_prompt_label = _label("", 20, Color(1, 0.95, 0.8))
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pbox.add_child(_prompt_label)
	_prompt_bar = ProgressBar.new()
	_prompt_bar.custom_minimum_size = Vector2(440, 8)
	_prompt_bar.show_percentage = false
	_prompt_bar.max_value = 1.0
	var pfg := StyleBoxFlat.new()
	pfg.bg_color = Color(0.95, 0.75, 0.3)
	_prompt_bar.add_theme_stylebox_override("background", bg)
	_prompt_bar.add_theme_stylebox_override("fill", pfg)
	pbox.add_child(_prompt_bar)

	# Bannière (haut centre) + message bref + compte à rebours
	var bbox := VBoxContainer.new()
	bbox.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	bbox.offset_left = -500
	bbox.offset_right = 500
	bbox.offset_top = 120
	bbox.offset_bottom = 260
	root.add_child(bbox)
	_banner_title = _label("", 46, Color(0.96, 0.9, 0.72))
	_banner_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bbox.add_child(_banner_title)
	_banner_sub = _label("", 20, Color(0.9, 0.88, 0.82))
	_banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bbox.add_child(_banner_sub)
	_flash_label = _label("", 26, Color(0.95, 0.8, 0.45))
	_flash_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bbox.add_child(_flash_label)
	_timer_label = _label("", 54, Color(1, 0.5, 0.35))
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bbox.add_child(_timer_label)

	# Rappel des commandes (bas centre, disparaît)
	_hint_label = _label("ZQSD/WASD se déplacer · Clic droit viser · R recharger · 1-2-3 armes · G grenade · C accroupi · Maj sprint · Échap pause",
		15, Color(0.9, 0.9, 0.85))
	_hint_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_hint_label.offset_left = -600
	_hint_label.offset_right = 600
	_hint_label.offset_top = -40
	_hint_label.offset_bottom = -16
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_hint_label)


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", maxi(4, size / 5))
	return l


func bind(p: Player) -> void:
	player = p
	p.damaged.connect(_on_damaged)
	p.hit_confirmed.connect(_on_hit)


# --- API utilisée par la mission ------------------------------------------------------

func set_objective(text: String, pos: Variant) -> void:
	_obj_label.text = text
	objective_pos = pos


func set_counter(text: String) -> void:
	_counter_label.text = text


func banner(title: String, sub: String, duration: float) -> void:
	_banner_title.text = title
	_banner_sub.text = sub
	_banner_t = duration


func flash_message(text: String) -> void:
	_flash_label.text = text
	_flash_t = 2.5


func set_timer(seconds: float) -> void:
	_timer_label.text = "" if seconds < 0.0 else "%.1f" % maxf(seconds, 0.0)


# --- Événements ----------------------------------------------------------------------

func _on_damaged(from_pos: Vector3) -> void:
	_hurt_pulse = 1.0
	_damage_dirs.append({"pos": from_pos, "t": 1.6})
	if _damage_dirs.size() > 6:
		_damage_dirs.pop_front()


func _on_hit(killed: bool, _headshot: bool) -> void:
	_hit_t = 0.25
	_hit_kill = killed


func _process(delta: float) -> void:
	if player == null:
		return
	var w := player.weapon()
	_weapon_label.text = w.display_name
	_ammo_label.text = "%d  |  %d" % [player.mags[player.current], w.reserve]
	if player.reloading:
		_ammo_label.text = "Rechargement…"
	elif player.mags[player.current] == 0:
		_ammo_label.text = "VIDE  |  %d" % w.reserve
	_gren_label.text = "Grenades : %d" % player.grenades
	_health_bar.value = player.health

	if player.can_interact():
		_prompt_label.text = player.interact_target.prompt
		_prompt_bar.visible = true
		_prompt_bar.value = player.interact_progress
	else:
		_prompt_label.text = ""
		_prompt_bar.visible = false

	_hit_t = maxf(0.0, _hit_t - delta)
	_hurt_pulse = maxf(0.0, _hurt_pulse - delta * 2.5)
	for d in _damage_dirs:
		d["t"] = float(d["t"]) - delta
	_damage_dirs = _damage_dirs.filter(func(d: Dictionary) -> bool: return float(d["t"]) > 0.0)
	var low := 1.0 - player.health / Player.MAX_HEALTH
	_vig_mat.set_shader_parameter("hurt", clampf(low * 0.9 + _hurt_pulse * 0.35, 0.0, 1.0))

	_banner_t -= delta
	var ba := clampf(_banner_t, 0.0, 1.0)
	_banner_title.modulate.a = ba
	_banner_sub.modulate.a = ba
	_flash_t -= delta
	_flash_label.modulate.a = clampf(_flash_t, 0.0, 1.0)
	_hint_t -= delta
	_hint_label.modulate.a = clampf(_hint_t / 2.0, 0.0, 1.0)
	_overlay.queue_redraw()


# --- Dessin : réticule, marqueurs, indicateurs ---------------------------------------

func _draw_overlay(c: Control) -> void:
	if player == null:
		return
	var size := c.size
	var center := size * 0.5
	var cam := player.camera
	var white := Color(1, 1, 1, 0.9)

	# Réticule : écartement = dispersion réelle projetée à l'écran
	var cross_a := (1.0 - smoothstep(0.3, 0.7, player.ads_t)) * (0.0 if player.sprinting or player.dead else 1.0)
	if cross_a > 0.01:
		var gap := tan(deg_to_rad(player.get_spread_deg())) / tan(deg_to_rad(cam.fov) * 0.5) * size.y * 0.5
		gap = maxf(gap, 4.0)
		var col := Color(1, 1, 1, 0.85 * cross_a)
		var l := 10.0
		for dir: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
			c.draw_line(center + dir * gap, center + dir * (gap + l), Color(0, 0, 0, 0.5 * cross_a), 4.0)
			c.draw_line(center + dir * gap, center + dir * (gap + l), col, 2.0)

	# Marqueur d'impact
	if _hit_t > 0.0:
		var hc := Color(0.95, 0.2, 0.15, _hit_t * 4.0) if _hit_kill else Color(1, 1, 1, _hit_t * 4.0)
		for dir: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			var n := dir.normalized()
			c.draw_line(center + n * 7.0, center + n * 16.0, hc, 2.5)

	# Indicateurs de direction des dégâts
	var inv := player.global_transform.basis.inverse()
	for d in _damage_dirs:
		var local: Vector3 = inv * ((d["pos"] as Vector3) - player.global_position)
		var ang := atan2(local.x, -local.z) - PI * 0.5
		var a := clampf(float(d["t"]) / 1.6, 0.0, 1.0)
		c.draw_arc(center, 150.0, ang - 0.3, ang + 0.3, 16, Color(0.85, 0.1, 0.05, 0.75 * a), 10.0)

	# Grenade ennemie à proximité
	for g in get_tree().get_nodes_in_group("grenade"):
		var gr := g as Grenade
		if gr.is_live_threat() and gr.global_position.distance_to(player.global_position) < 9.0:
			var gl: Vector3 = inv * (gr.global_position - player.global_position)
			var ga := atan2(gl.x, -gl.z) - PI * 0.5
			var gp := center + Vector2(cos(ga), sin(ga)) * 110.0
			c.draw_circle(gp, 16.0, Color(0, 0, 0, 0.6))
			c.draw_circle(gp, 13.0, Color(0.95, 0.75, 0.2, 0.9), false, 2.5)
			c.draw_string(ThemeDB.fallback_font, gp + Vector2(-4, 6), "!", HORIZONTAL_ALIGNMENT_CENTER, -1, 18, Color(1, 0.85, 0.3))

	# Marqueur d'objectif
	if objective_pos != null and not player.dead:
		var wp: Vector3 = objective_pos
		var dist := player.global_position.distance_to(wp)
		var local := cam.global_transform.affine_inverse() * wp
		var sp: Vector2
		if local.z < -0.2:
			sp = cam.unproject_position(wp)
		else:
			# Derrière la caméra : on colle le marqueur au bord inférieur, du bon côté
			sp = Vector2(center.x + (1.0 if local.x >= 0.0 else -1.0) * size.x * 0.46, center.y)
		var m := 50.0
		sp = Vector2(clampf(sp.x, m, size.x - m), clampf(sp.y, m + 120.0, size.y - m))
		var gold := Color(0.95, 0.78, 0.35, 0.95)
		var pts := PackedVector2Array([sp + Vector2(0, -11), sp + Vector2(9, 0), sp + Vector2(0, 11), sp + Vector2(-9, 0)])
		c.draw_colored_polygon(pts, Color(0, 0, 0, 0.45))
		pts.append(pts[0])
		c.draw_polyline(pts, gold, 2.5)
		c.draw_string(ThemeDB.fallback_font, sp + Vector2(-40, 30), "%d m" % int(dist),
			HORIZONTAL_ALIGNMENT_CENTER, 80, 16, white)
