class_name Player
extends CharacterBody3D
## Joueur : déplacement FPS, visée, tir hitscan, grenades, interaction, santé régénérante.

signal died
signal damaged(from_pos: Vector3)
signal hit_confirmed(killed: bool, headshot: bool)
signal weapon_changed

const WALK_SPEED := 4.6
const SPRINT_SPEED := 7.0
const CROUCH_SPEED := 2.4
const ADS_SPEED := 2.8
const ACCEL_GROUND := 14.0
const ACCEL_AIR := 3.0
const JUMP_VELOCITY := 5.0
const GRAVITY := 15.0
const STAND_HEIGHT := 1.8
const CROUCH_HEIGHT := 1.15
const EYE_STAND := 1.62
const EYE_CROUCH := 1.0
const HIP_FOV := 75.0
const MAX_HEALTH := 100.0
const REGEN_DELAY := 4.5
const REGEN_RATE := 22.0

var head: Node3D
var camera: Camera3D
var view: WeaponView
var _shape: CollisionShape3D
var _capsule: CapsuleShape3D

var weapons: Array[WeaponData] = []
var mags: Array[int] = []
var current := 0
var grenades := 3

var health := MAX_HEALTH
var dead := false
var controls_enabled := true
var crouching := false
var sprinting := false
var aiming := false
var ads_t := 0.0          # 0 = hanche, 1 = visée complète
var crouch_t := 0.0
var reloading := false
var reload_progress := 0.0

var test_trigger := false   # tests automatisés : simule la gâchette
var interact_target: Interactable = null
var interact_progress := 0.0

var recoil := Vector2.ZERO   # x = tangage, y = lacet (radians) — décalage qui revient à zéro
var _regen_wait := 0.0
var _reload_left := 0.0
var _switch_left := 0.0
var _clock := 0.0
var _next_shot := 0.0
var _last_shot_time := -10.0
var _semi_ready := true
var _bloom := 0.0
var _shake := 0.0
var _grenade_cd := 0.0
var _step_acc := 0.0


func _ready() -> void:
	add_to_group("player")
	collision_layer = Game.LAYER_PLAYER
	collision_mask = Game.LAYER_WORLD | Game.LAYER_ENEMY
	floor_snap_length = 0.3
	_capsule = CapsuleShape3D.new()
	_capsule.radius = 0.35
	_capsule.height = STAND_HEIGHT
	_shape = CollisionShape3D.new()
	_shape.shape = _capsule
	_shape.position.y = STAND_HEIGHT / 2.0
	add_child(_shape)
	head = Node3D.new()
	head.position.y = EYE_STAND
	add_child(head)
	camera = Camera3D.new()
	camera.fov = HIP_FOV
	camera.near = 0.03
	camera.far = 600.0
	camera.current = true
	head.add_child(camera)
	view = WeaponView.new()
	camera.add_child(view)
	weapons = WeaponData.make_all()
	for w in weapons:
		mags.append(w.mag_size)
	view.set_weapon(weapons[current], true)


func weapon() -> WeaponData:
	return weapons[current]


# --- Entrées ---------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if dead or not controls_enabled:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		var k := Game.mouse_sensitivity * _ads_sens_factor()
		rotate_y(-motion.relative.x * k)
		var dy := motion.relative.y * k * (-1.0 if Game.invert_y else 1.0)
		head.rotation.x = clampf(head.rotation.x - dy, deg_to_rad(-89.0), deg_to_rad(89.0))
		view.add_sway(motion.relative)
	elif event.is_action_pressed("weapon_1"):
		switch_to(0)
	elif event.is_action_pressed("weapon_2"):
		switch_to(1)
	elif event.is_action_pressed("weapon_3"):
		switch_to(2)
	elif event.is_action_pressed("weapon_next"):
		switch_to(wrapi(current + 1, 0, weapons.size()))
	elif event.is_action_pressed("weapon_prev"):
		switch_to(wrapi(current - 1, 0, weapons.size()))
	elif event.is_action_pressed("reload"):
		start_reload()
	elif event.is_action_pressed("grenade"):
		throw_grenade()


## Sensibilité réduite en visée : tan(fov_visée/2) / tan(fov_hanche/2).
func _ads_sens_factor() -> float:
	return tan(deg_to_rad(camera.fov) * 0.5) / tan(deg_to_rad(HIP_FOV) * 0.5)


# --- Boucle physique ---------------------------------------------------------

func _physics_process(delta: float) -> void:
	_clock += delta
	if dead:
		velocity.x = move_toward(velocity.x, 0.0, delta * 10.0)
		velocity.z = move_toward(velocity.z, 0.0, delta * 10.0)
		velocity.y -= GRAVITY * delta
		move_and_slide()
		return
	_update_movement(delta)
	_update_weapon(delta)
	_update_interact(delta)
	_update_health(delta)
	if global_position.y < -30.0:
		take_damage(999.0, global_position)


func _update_movement(delta: float) -> void:
	var input_dir := Vector2.ZERO
	if controls_enabled:
		input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	crouching = controls_enabled and Input.is_action_pressed("crouch")
	aiming = controls_enabled and Input.is_action_pressed("aim") and _switch_left <= 0.0 \
		and not reloading and interact_progress <= 0.0
	sprinting = controls_enabled and Input.is_action_pressed("sprint") and input_dir.y < -0.3 \
		and not crouching and not aiming
	if sprinting and reloading:
		sprinting = false

	var speed := WALK_SPEED
	if crouching:
		speed = CROUCH_SPEED
	elif aiming:
		speed = ADS_SPEED
	elif sprinting:
		speed = SPRINT_SPEED
	speed *= weapon().move_mult

	var dir := transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)
	dir.y = 0.0
	dir = dir.normalized() * minf(1.0, input_dir.length())
	var accel := ACCEL_GROUND if is_on_floor() else ACCEL_AIR
	var k := 1.0 - exp(-accel * delta)
	velocity.x = lerpf(velocity.x, dir.x * speed, k)
	velocity.z = lerpf(velocity.z, dir.z * speed, k)
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	elif controls_enabled and Input.is_action_just_pressed("jump") and not crouching:
		velocity.y = JUMP_VELOCITY
	move_and_slide()

	# Accroupi : capsule et caméra
	crouch_t = move_toward(crouch_t, 1.0 if crouching else 0.0, delta * 6.0)
	var h := lerpf(STAND_HEIGHT, CROUCH_HEIGHT, crouch_t)
	_capsule.height = h
	_shape.position.y = h / 2.0
	head.position.y = lerpf(EYE_STAND, EYE_CROUCH, crouch_t)

	# Bruits de pas
	var hspeed := Vector2(velocity.x, velocity.z).length()
	if is_on_floor() and hspeed > 1.0:
		_step_acc += hspeed * delta
		var stride := 2.6 if sprinting else 2.0
		if _step_acc > stride:
			_step_acc = 0.0
			var surface := "step_stone" if LevelBuilder.is_paved(global_position) else "step_grass"
			Sfx.play(surface, -16.0 if crouching else -9.0, 0.1)


func _update_weapon(delta: float) -> void:
	var w := weapon()
	ads_t = move_toward(ads_t, 1.0 if aiming else 0.0, delta / w.ads_time)
	var sprint_fov := 6.0 if sprinting and Vector2(velocity.x, velocity.z).length() > 4.0 else 0.0
	var target_fov := lerpf(HIP_FOV, w.ads_fov, smoothstep(0.0, 1.0, ads_t)) + sprint_fov
	camera.fov = lerpf(camera.fov, target_fov, 1.0 - exp(-18.0 * delta))

	_grenade_cd = maxf(0.0, _grenade_cd - delta)
	if _switch_left > 0.0:
		_switch_left -= delta
	if reloading:
		_reload_left -= delta
		reload_progress = 1.0 - _reload_left / w.reload_time
		if _reload_left <= 0.0:
			_finish_reload()

	var trigger := test_trigger or (controls_enabled and Input.is_action_pressed("fire") \
		and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED)
	if not trigger:
		_semi_ready = true
	var can_fire := _switch_left <= 0.0 and not reloading and not sprinting and interact_progress <= 0.0
	if trigger and can_fire:
		if mags[current] <= 0:
			if _semi_ready:
				_semi_ready = false
				Sfx.play("click")
				start_reload()
		elif w.automatic:
			# Cadence planifiée sur une horloge : indépendante du framerate
			var interval := 1.0 / w.fire_rate
			if _next_shot < _clock - interval:
				_next_shot = _clock
			while _next_shot <= _clock and mags[current] > 0:
				_fire(w)
				_next_shot += interval
		elif _semi_ready and _clock >= _next_shot:
			_semi_ready = false
			_next_shot = _clock + 1.0 / w.fire_rate
			_fire(w)

	# Retour progressif du recul et de la dispersion
	if _clock - _last_shot_time > 0.08:
		recoil = recoil.lerp(Vector2.ZERO, 1.0 - exp(-w.recovery * delta))
	if _clock - _last_shot_time > 0.25:
		_bloom = move_toward(_bloom, 0.0, delta * w.bloom_max * 3.0)
	_shake = move_toward(_shake, 0.0, delta * 1.8)
	camera.rotation = Vector3(recoil.x, recoil.y, sin(_clock * 37.0) * _shake * 0.02)
	camera.h_offset = randf_range(-1.0, 1.0) * _shake * 0.04
	camera.v_offset = randf_range(-1.0, 1.0) * _shake * 0.04


func _process(delta: float) -> void:
	if view:
		view.update_view(delta, self)


## Demi-angle de dispersion actuel en degrés (sert aussi au réticule du HUD).
func get_spread_deg() -> float:
	var w := weapon()
	var s := lerpf(w.hip_spread, w.ads_spread, ads_t)
	s += Vector2(velocity.x, velocity.z).length() * 0.25 * (1.0 - ads_t * 0.7)
	if not is_on_floor():
		s += 3.0
	if crouching:
		s *= 0.75
	return s + _bloom * (1.0 - ads_t * 0.5)


func _fire(w: WeaponData) -> void:
	mags[current] -= 1
	_last_shot_time = _clock
	Game.stats["shots"] += 1
	var spread := get_spread_deg()
	_bloom = minf(_bloom + w.bloom, w.bloom_max)
	var ads_k := lerpf(1.0, 0.65, ads_t)
	recoil.x = minf(recoil.x + deg_to_rad(w.recoil_v) * ads_k * randf_range(0.85, 1.15), deg_to_rad(12.0))
	recoil.y += deg_to_rad(randf_range(-w.recoil_h, w.recoil_h)) * ads_k
	view.kick(w)
	Sfx.play(w.sound, -2.0)
	Game.make_noise(global_position, w.noise_radius)

	# Tir hitscan depuis la caméra, dispersion échantillonnée sur un disque
	var r := tan(deg_to_rad(spread)) * sqrt(randf())
	var a := randf() * TAU
	var b := camera.global_transform.basis
	var dir := (-b.z + b.x * cos(a) * r + b.y * sin(a) * r).normalized()
	var from := camera.global_position
	var to := from + dir * w.max_range
	var q := PhysicsRayQueryParameters3D.create(from, to, Game.LAYER_WORLD | Game.LAYER_ENEMY, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var end := to
	if not hit.is_empty():
		end = hit["position"]
		var normal: Vector3 = hit["normal"]
		var col: Object = hit["collider"]
		if col != null and col.has_method("take_bullet"):
			var res: Dictionary = col.call("take_bullet", w.damage_at(from.distance_to(end)), end, w.head_mult, dir)
			if res.get("hit", false):
				register_hit(res.get("killed", false), res.get("headshot", false))
		else:
			Fx.impact(end, normal)
	if randf() < 0.3:
		Fx.tracer(view.muzzle_position(), end)
	if mags[current] == 0 and w.id == "garand":
		Sfx.play("ping", -6.0, 0.02)   # éjection du clip en bloc


func register_hit(killed: bool, headshot: bool) -> void:
	Game.stats["hits"] += 1
	if killed:
		Game.stats["kills"] += 1
		if headshot:
			Game.stats["headshots"] += 1
	Sfx.play("kill" if killed else "hitmarker", -6.0, 0.02)
	hit_confirmed.emit(killed, headshot)


func start_reload() -> void:
	var w := weapon()
	if reloading or dead or _switch_left > 0.0 or mags[current] >= w.mag_size or w.reserve <= 0:
		return
	reloading = true
	_reload_left = w.reload_time
	reload_progress = 0.0
	view.play_reload(w.reload_time)
	Sfx.play("reload", -6.0)
	get_tree().create_timer(w.reload_time * 0.75, false).timeout.connect(func() -> void:
		if reloading:
			Sfx.play("click", -4.0))


func _finish_reload() -> void:
	reloading = false
	var w := weapon()
	var take := mini(w.mag_size - mags[current], w.reserve)
	mags[current] += take
	w.reserve -= take


func switch_to(i: int) -> void:
	if i == current or i < 0 or i >= weapons.size() or dead:
		return
	reloading = false
	current = i
	_switch_left = 0.45
	_bloom = 0.0
	view.set_weapon(weapons[i])
	weapon_changed.emit()
	Sfx.play("click", -8.0)


func throw_grenade() -> void:
	if grenades <= 0 or _grenade_cd > 0.0 or _switch_left > 0.0 or dead:
		return
	grenades -= 1
	_grenade_cd = 1.0
	var g := Grenade.new()
	g.from_player = true
	get_tree().current_scene.add_child(g)
	var b := camera.global_transform.basis
	g.global_position = camera.global_position - b.z * 0.6 + b.x * 0.15
	g.linear_velocity = -b.z * 16.0 + Vector3.UP * 3.5 + velocity * 0.5
	g.add_collision_exception_with(self)
	view.play_throw()


func add_ammo() -> void:
	for w in weapons:
		w.reserve = mini(w.reserve + w.mag_size, w.reserve_max)
	if randf() < 0.5:
		grenades = mini(grenades + 1, 4)
	Sfx.play("pickup", -6.0)


func add_shake(amount: float) -> void:
	_shake = clampf(_shake + amount, 0.0, 1.5)


# --- Santé ---------------------------------------------------------------------

func take_damage(amount: float, from_pos: Vector3) -> void:
	if dead:
		return
	health -= amount
	Game.stats["damage_taken"] += amount
	_regen_wait = REGEN_DELAY
	add_shake(0.25)
	damaged.emit(from_pos)
	Sfx.play("hurt", -3.0, 0.12)
	if health <= 0.0:
		_die()


func _update_health(delta: float) -> void:
	if _regen_wait > 0.0:
		_regen_wait -= delta
	elif health < MAX_HEALTH:
		health = minf(MAX_HEALTH, health + REGEN_RATE * delta)


func _die() -> void:
	health = 0.0
	dead = true
	controls_enabled = false
	reloading = false
	view.visible = false
	var tw := create_tween()
	tw.tween_property(head, "position:y", 0.35, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(head, "rotation:z", deg_to_rad(75.0), 0.7)
	died.emit()


# --- Interaction ---------------------------------------------------------------

func can_interact() -> bool:
	var t := interact_target
	if t == null or not is_instance_valid(t) or not t.enabled or dead:
		return false
	var to := t.global_position - global_position
	to.y = 0.0
	if to.length() < 1.0:
		return true
	var fwd := -global_transform.basis.z
	return fwd.dot(to.normalized()) > 0.5


func _update_interact(delta: float) -> void:
	if not can_interact() or not controls_enabled or not Input.is_action_pressed("interact"):
		interact_progress = 0.0
		return
	reloading = false
	interact_progress += delta / interact_target.hold_time
	if interact_progress >= 1.0:
		interact_progress = 0.0
		interact_target.complete()
