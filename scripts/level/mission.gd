extends Node3D
## Mission « Opération Aube » : environnement, niveau, unités et enchaînement des objectifs.
## 1. Franchir le bocage -> 2. Nettoyer la place -> 3. Poser la charge sur le 88
## -> 4. S'éloigner -> 5. Repousser la contre-attaque -> 6. Rejoindre le ralliement.

enum Obj { REACH_VILLAGE, CLEAR_SQUARE, PLANT_CHARGE, ESCAPE_BLAST, COUNTER_ATTACK, RALLY, DONE }

const START := Vector3(0, 0.1, 100)
const VILLAGE_GATE := Vector3(0, 0, 40)
const SQUARE := Vector3(0, 0, -2)
const FLAK_POS := Vector3(50, 0, -2)
const RALLY := Vector3(-58, 0, -2)
const BLAST_TIME := 10.0
# Points de contrôle : position et lacet du joueur à la reprise
const CHECKPOINTS := [
	[Vector3(0, 0.1, 100), 0.0], [Vector3(0, 0.1, 40), 0.0],
	[Vector3(0, 0.1, 4), -90.0], [Vector3(28, 0.1, -2), 0.0],
]
const SQUAD := [["Sgt Miller", Vector3(-2.5, 0, 2.5)], ["Sdt Novak", Vector3(2.5, 0, 3.5)]]

var player: Player
var allies: Array[Ally] = []
var hud: Hud
var pause_menu: PauseMenu
var builder: LevelBuilder
var obj := Obj.REACH_VILLAGE
var charge: Interactable
var ended := false
var _blast_left := 0.0
var _wave_delay := -1.0
var _charge_marker: MeshInstance3D


func _ready() -> void:
	Fx.reset()
	_setup_environment()
	builder = LevelBuilder.new()
	builder.build(self)
	var cp := clampi(Game.checkpoint, 0, CHECKPOINTS.size() - 1)
	player = Player.new()
	player.position = CHECKPOINTS[cp][0]
	player.rotation.y = deg_to_rad(CHECKPOINTS[cp][1])
	add_child(player)
	player.died.connect(_on_player_died)
	for def: Array in SQUAD:
		var a := Ally.new()
		a.callsign = def[0]
		a.slot = def[1]
		add_child(a)
		a.teleport_to_slot()
		allies.append(a)
	_spawn_initial_enemies()
	_setup_triggers()
	hud = Hud.new()
	add_child(hud)
	hud.bind(player)
	pause_menu = PauseMenu.new()
	add_child(pause_menu)
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	match cp:
		0:
			_set_objective(Obj.REACH_VILLAGE, false)
			hud.banner("OPÉRATION AUBE", "Saint-Aubin-des-Haies — Normandie, 7 juin 1944", 6.0)
		1:
			_set_objective(Obj.CLEAR_SQUARE, false)
		2:
			_set_objective(Obj.PLANT_CHARGE, false)
		3:
			builder.destroy_flak()
			_set_objective(Obj.COUNTER_ATTACK, false)
	if cp > 0:
		hud.banner("POINT DE CONTRÔLE", "Reprise de la mission", 3.0)


func _setup_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.3, 0.42, 0.62)
	sky_mat.sky_horizon_color = Color(0.93, 0.68, 0.48)
	sky_mat.ground_horizon_color = Color(0.62, 0.52, 0.42)
	sky_mat.ground_bottom_color = Color(0.2, 0.19, 0.17)
	sky_mat.sun_angle_max = 25.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.fog_enabled = true
	env.fog_light_color = Color(0.86, 0.72, 0.6)
	env.fog_density = 0.006
	env.fog_sky_affect = 0.25
	env.ssao_enabled = true
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.85
	env.adjustment_contrast = 1.05
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	# Soleil bas à l'est : lumière d'aube rasante
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-24, 68, 0)
	sun.light_color = Color(1.0, 0.82, 0.62)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 140.0
	add_child(sun)


# --- Unités ------------------------------------------------------------------------

## Zones déjà nettoyées au point de contrôle courant : on ne les repeuple pas.
func _zone_cleared(zone: String) -> bool:
	var cp := Game.checkpoint
	match zone:
		"bocage":
			return cp >= 1
		"street", "square":
			return cp >= 2
		"flak":
			return cp >= 3
	return false


func _enemy(pos: Vector3, zone: String, kind := "rifle", yaw_deg := 180.0, patrol: Array = [],
		static_post := false) -> Enemy:
	if _zone_cleared(zone):
		return null
	var e := Enemy.new()
	e.kind = kind
	e.zone = zone
	e.static_post = static_post or kind == "mg"
	e.position = pos
	e.rotation.y = deg_to_rad(yaw_deg)
	for p: Vector3 in patrol:
		e.patrol_points.append(p)
	add_child(e)
	e.died.connect(_on_enemy_died)
	return e


func _spawn_initial_enemies() -> void:
	# Bocage
	_enemy(Vector3(-3, 0, 75.5), "bocage")
	_enemy(Vector3(12, 0, 75.5), "bocage")
	_enemy(Vector3(-16, 0, 55.5), "bocage")
	_enemy(Vector3(8, 0, 55.5), "bocage", "smg", 180.0, [Vector3(8, 0, 55.5), Vector3(-4, 0, 55.5)])
	_enemy(Vector3(30, 0, 62), "bocage", "rifle", 210.0)
	# Rue
	_enemy(Vector3(5.5, 0, 28.5), "street")
	_enemy(Vector3(-6, 0, 32), "street", "smg", 160.0)
	# Place (objectif)
	_enemy(Vector3(2, 0, -13.2), "square", "mg")
	_enemy(Vector3(-12, 0, 6), "square", "rifle", 170.0)
	_enemy(Vector3(13.5, 0, -1), "square", "rifle", 200.0)
	_enemy(Vector3(-23, 0, -10.5), "square", "smg", -135.0)
	_enemy(Vector3(8, 0, -15), "square", "rifle", 180.0)
	_enemy(Vector3(-7, 0, -15), "square", "rifle", 170.0)
	_enemy(Vector3(-4, 0, 7), "square", "smg", 180.0, [Vector3(-4, 0, 7), Vector3(6, 0, 7)])
	# Canon de 88
	_enemy(Vector3(45, 0, -6), "flak", "rifle", 90.0)
	_enemy(Vector3(54, 0, 3), "flak", "smg", 90.0, [Vector3(54, 0, 3), Vector3(54, 0, -8)])
	_enemy(Vector3(47, 0, 4), "flak", "rifle", 60.0)


func _spawn_counter_attack() -> void:
	var defs := [
		[Vector3(-8, 0, -75), "rifle"], [Vector3(6, 0, -80), "smg"], [Vector3(20, 0, -70), "rifle"],
		[Vector3(-25, 0, -66), "smg"], [Vector3(45, 0, -55), "rifle"], [Vector3(62, 0, -30), "smg"],
		[Vector3(35, 0, -70), "rifle"],
	]
	for d: Array in defs:
		var e := _enemy(d[0], "counter", d[1], 0.0)
		e.hunter = true
		e.call_deferred("_alert_to", player.global_position, true)


func alive_in(zone: String) -> int:
	var n := 0
	for e in get_tree().get_nodes_in_group("enemy"):
		var en := e as Enemy
		if en.zone == zone and not en.is_dead():
			n += 1
	return n


func total_in(zone: String) -> int:
	var n := 0
	for e in get_tree().get_nodes_in_group("enemy"):
		if (e as Enemy).zone == zone:
			n += 1
	return n


# --- Déclencheurs ------------------------------------------------------------------

func _trigger(pos: Vector3, size: Vector3, callback: Callable) -> Area3D:
	var a := Area3D.new()
	a.collision_layer = 0
	a.collision_mask = Game.LAYER_PLAYER
	var cs := CollisionShape3D.new()
	var s := BoxShape3D.new()
	s.size = size
	cs.shape = s
	a.add_child(cs)
	a.position = pos + Vector3.UP * size.y * 0.5
	add_child(a)
	a.body_entered.connect(func(b: Node3D) -> void:
		if b is Player:
			callback.call())
	return a


func _setup_triggers() -> void:
	_trigger(VILLAGE_GATE, Vector3(80, 6, 4), _on_village_reached)
	_trigger(RALLY, Vector3(10, 6, 10), _on_rally_reached)
	charge = Interactable.create("Maintenir [E] pour poser la charge", 3.0, 4.0)
	charge.position = FLAK_POS + Vector3.UP
	charge.enabled = false
	add_child(charge)
	charge.completed.connect(_on_charge_planted)


func _on_village_reached() -> void:
	if obj == Obj.REACH_VILLAGE:
		_set_objective(Obj.CLEAR_SQUARE)


func _on_rally_reached() -> void:
	if obj == Obj.RALLY:
		_finish(true)


func _on_charge_planted() -> void:
	if obj != Obj.PLANT_CHARGE:
		return
	var m := MeshInstance3D.new()
	m.mesh = builder.boxm(Vector3(0.4, 0.3, 0.3))
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.35, 0.2)
	mat.emission_enabled = true
	mat.emission = Color(1, 0.1, 0.05)
	mat.emission_energy_multiplier = 0.0
	m.material_override = mat
	add_child(m)
	m.global_position = FLAK_POS + Vector3(0, 1.0, 1.7)
	_charge_marker = m
	Sfx.play("click")
	_set_objective(Obj.ESCAPE_BLAST)


# --- Objectifs ------------------------------------------------------------------------

func _set_objective(o: Obj, announce := true) -> void:
	if announce and o != Obj.REACH_VILLAGE:
		hud.flash_message("Objectif accompli")
		Sfx.play("ui")
	obj = o
	# Points de contrôle enregistrés à chaque étape majeure
	var cp_for := {Obj.CLEAR_SQUARE: 1, Obj.PLANT_CHARGE: 2, Obj.COUNTER_ATTACK: 3}
	if cp_for.has(o) and int(cp_for[o]) > Game.checkpoint:
		Game.checkpoint = cp_for[o]
		if announce:
			hud.flash_message("Objectif accompli — point de contrôle")
	match o:
		Obj.REACH_VILLAGE:
			hud.set_objective("Franchissez le bocage et atteignez l'entrée du village", VILLAGE_GATE + Vector3.UP)
		Obj.CLEAR_SQUARE:
			hud.set_objective("Neutralisez les défenseurs de la place du village", SQUARE + Vector3.UP)
			_update_counter()
			if alive_in("square") == 0:
				_set_objective(Obj.PLANT_CHARGE)
		Obj.PLANT_CHARGE:
			charge.enabled = true
			hud.set_objective("Posez une charge sur le canon de 88, à l'est du village", FLAK_POS + Vector3.UP * 3.0)
		Obj.ESCAPE_BLAST:
			_blast_left = BLAST_TIME
			hud.set_objective("Éloignez-vous du canon !", null)
		Obj.COUNTER_ATTACK:
			_spawn_counter_attack()
			hud.set_objective("Repoussez la contre-attaque venue du nord", null)
			hud.banner("CONTRE-ATTAQUE", "L'ennemi arrive du nord", 4.0)
			_update_counter()
		Obj.RALLY:
			hud.set_objective("Rejoignez le point de ralliement à l'ouest (fumée verte)", RALLY + Vector3.UP * 2.0)


func _update_counter() -> void:
	match obj:
		Obj.CLEAR_SQUARE:
			hud.set_counter("Défenseurs restants : %d" % alive_in("square"))
		Obj.COUNTER_ATTACK:
			hud.set_counter("Assaillants restants : %d" % alive_in("counter"))
		_:
			hud.set_counter("")


func _on_enemy_died(_e: Enemy) -> void:
	_update_counter()
	if obj == Obj.CLEAR_SQUARE and alive_in("square") == 0:
		_set_objective(Obj.PLANT_CHARGE)
	elif obj == Obj.COUNTER_ATTACK and alive_in("counter") == 0:
		_set_objective(Obj.RALLY)


func _process(delta: float) -> void:
	if ended:
		return
	Game.stats["time"] += delta
	if obj == Obj.ESCAPE_BLAST:
		_blast_left -= delta
		hud.set_timer(_blast_left)
		if _charge_marker:
			var mat := _charge_marker.material_override as StandardMaterial3D
			mat.emission_energy_multiplier = 3.0 if fmod(_blast_left, 0.5) < 0.25 else 0.0
		if _blast_left <= 0.0:
			hud.set_timer(-1.0)
			_flak_explode()
	if _wave_delay > 0.0:
		_wave_delay -= delta
		if _wave_delay <= 0.0:
			_set_objective(Obj.COUNTER_ATTACK)


func _flak_explode() -> void:
	if _charge_marker:
		_charge_marker.queue_free()
		_charge_marker = null
	Fx.explosion(FLAK_POS + Vector3.UP, 2.2)
	get_tree().create_timer(0.25, false).timeout.connect(func() -> void: Fx.explosion(FLAK_POS + Vector3(1.5, 2, -1), 1.4))
	get_tree().create_timer(0.5, false).timeout.connect(func() -> void: Fx.explosion(FLAK_POS + Vector3(-1, 1.5, 1.5), 1.2))
	builder.destroy_flak()
	Game.make_noise(FLAK_POS, 200.0)
	var d := player.global_position.distance_to(FLAK_POS)
	if d < 14.0:
		player.take_damage(250.0 * (1.0 - d / 14.0), FLAK_POS)
	for e in get_tree().get_nodes_in_group("enemy"):
		var en := e as Enemy
		var ed := en.global_position.distance_to(FLAK_POS)
		if ed < 12.0:
			en.take_explosion(250.0 * (1.0 - ed / 12.0), FLAK_POS)
	if not player.dead:
		hud.flash_message("Canon détruit !")
		obj = Obj.DONE
		_wave_delay = 3.0


# --- Fin de mission -------------------------------------------------------------------

func _on_player_died() -> void:
	get_tree().create_timer(2.5, false).timeout.connect(func() -> void: _finish(false))


func _finish(victory: bool) -> void:
	if ended:
		return
	ended = true
	player.controls_enabled = false
	pause_menu.allowed = false
	Game.last_result = Game.stats.duplicate()
	Game.last_result["victory"] = victory
	Game.last_result["difficulty"] = Game.difficulty
	if victory:
		hud.banner("MISSION ACCOMPLIE", "La route de la côte est ouverte", 3.0)
	var delay := 2.5 if victory else 0.2
	get_tree().create_timer(delay, false).timeout.connect(func() -> void:
		var screen := EndScreen.new()
		add_child(screen)
		screen.show_result(Game.last_result))


func _unhandled_input(event: InputEvent) -> void:
	# Reprendre le contrôle de la souris après un clic (perte de focus, etc.)
	if event is InputEventMouseButton and event.pressed and not ended and not get_tree().paused \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
