class_name Ally
extends CharacterBody3D
## Coéquipier contrôlé par l'IA : suit le joueur en formation, engage les ennemis visibles,
## attire une partie du feu ennemi. Invulnérable (comme dans la plupart des FPS à escouade) :
## une blessure le fait réagir mais ne le tue pas, pour éviter un échec de mission injuste.

const RUN := 5.4
const WALK := 2.8
const GRAVITY := 15.0
const SCAN_RANGE := 50.0
const DAMAGE := 30.0
const ACCURACY := 0.35

var callsign := "Allié"
var slot := Vector3(-2.5, 0, 2.5)   # position dans le repère du joueur (derrière lui)
var model: SoldierModel
var dead := false          # interface commune avec Player (lue par l'IA ennemie)
var crouching := false
var crouch_t := 0.0

var _player: Player
var _agent: NavigationAgent3D
var _target: Enemy = null
var _scan := 0.0
var _shot_cd := 1.0
var _repath := 0.0
var _crouch_timer := 0.0


func _ready() -> void:
	add_to_group("ally")
	collision_layer = Game.LAYER_ALLY
	collision_mask = Game.LAYER_WORLD | Game.LAYER_ENEMY
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.9
	add_child(cs)
	_agent = NavigationAgent3D.new()
	_agent.path_desired_distance = 0.8
	_agent.target_desired_distance = 1.2
	_agent.radius = 0.4
	add_child(_agent)
	model = SoldierModel.new()
	model.faction = "allied"
	model.weapon_kind = "rifle"
	add_child(model)
	var tag := Label3D.new()
	tag.text = callsign
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	tag.fixed_size = true
	tag.pixel_size = 0.0012
	tag.font_size = 22
	tag.outline_size = 6
	tag.modulate = Color(0.55, 0.95, 0.5)
	tag.position.y = 2.15
	tag.visibility_range_end = 40.0
	add_child(tag)


func _get_player() -> Player:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Player
	return _player


## Appelé par les ennemis qui le touchent : réaction visuelle uniquement.
func take_damage(_amount: float, from_pos: Vector3) -> void:
	if randf() < 0.4:
		model.play_action("Hit_A")
	if _target == null:
		_face(from_pos, 1.0)


## Replace le coéquipier près de sa place (point de contrôle, retard trop important).
func teleport_to_slot() -> void:
	var p := _get_player()
	if p:
		global_position = p.global_transform * slot + Vector3.UP * 0.1
		velocity = Vector3.ZERO


func _physics_process(delta: float) -> void:
	var p := _get_player()
	if p == null:
		return
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	_scan -= delta
	if _scan <= 0.0:
		_scan = 0.3
		_target = _find_target()
	_shot_cd -= delta

	var slot_pos := p.global_transform * slot
	var to_slot := slot_pos - global_position
	to_slot.y = 0.0
	var dist_slot := to_slot.length()
	if dist_slot > 70.0:
		teleport_to_slot()
		return

	var speed := 0.0
	if _target and dist_slot < 8.0:
		# Combat : on tient la position et on tire
		_stop()
		_face(_target.global_position, delta)
		_crouch_timer -= delta
		if _crouch_timer <= 0.0:
			_crouch_timer = randf_range(2.0, 5.0)
			crouching = randf() < 0.5
		if _shot_cd <= 0.0:
			_shoot()
	else:
		crouching = false
		if dist_slot > 2.5:
			speed = RUN if dist_slot > 7.0 else WALK
			_move_to(slot_pos, speed, delta)
		else:
			_stop()
			var look := _target.global_position if _target else global_position - p.global_basis.z
			_face(look, delta)
	move_and_slide()
	crouch_t = move_toward(crouch_t, 1.0 if crouching else 0.0, delta * 4.0)
	model.set_motion(Vector2(velocity.x, velocity.z).length(), 1.0 if _target else 0.0, crouch_t)


func _find_target() -> Enemy:
	var eye := global_position + Vector3.UP * lerpf(1.6, 1.05, crouch_t)
	var space := get_world_3d().direct_space_state
	var best: Enemy = null
	var best_d := SCAN_RANGE
	for e in get_tree().get_nodes_in_group("enemy"):
		var en := e as Enemy
		if en.is_dead():
			continue
		var d := global_position.distance_to(en.global_position)
		if d > best_d:
			continue
		var q := PhysicsRayQueryParameters3D.create(eye, en.global_position + Vector3.UP * 1.2,
			Game.LAYER_WORLD | Game.LAYER_ENEMY, [get_rid()])
		var hit := space.intersect_ray(q)
		if not hit.is_empty() and hit["collider"] == en:
			best = en
			best_d = d
	return best


func _shoot() -> void:
	_shot_cd = randf_range(1.0, 1.8)
	var muzzle := model.gun_tip.global_position
	var aim := _target.global_position + Vector3.UP * 1.2
	var dist := muzzle.distance_to(aim)
	Sfx.play_at("rifle", muzzle, -4.0)
	Fx.muzzle_flash(muzzle)
	model.play_shoot()
	Game.make_noise(global_position, 40.0)
	if randf() < ACCURACY * clampf(1.2 - dist / SCAN_RANGE, 0.3, 1.0):
		_target.take_ally_hit(DAMAGE, global_position)
		Fx.tracer(muzzle, aim, Color(0.9, 1.0, 0.7))
	else:
		var miss := aim + Vector3(randf_range(-1, 1), randf_range(-0.3, 1.0), randf_range(-1, 1)).normalized() * 1.5
		Fx.tracer(muzzle, miss + (miss - muzzle).normalized() * 20.0, Color(0.9, 1.0, 0.7))


func _move_to(pos: Vector3, speed: float, delta: float) -> void:
	_repath -= delta
	if _repath <= 0.0:
		_repath = 0.4
		_agent.target_position = pos
	if _agent.is_navigation_finished():
		_stop()
		return
	var dir := _agent.get_next_path_position() - global_position
	dir.y = 0.0
	if dir.length() < 0.05:
		_stop()
		return
	dir = dir.normalized()
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	_face(global_position + dir, delta * 1.5)


func _stop() -> void:
	velocity.x = 0.0
	velocity.z = 0.0


func _face(pos: Vector3, delta: float) -> void:
	var d := pos - global_position
	if Vector2(d.x, d.z).length() > 0.01:
		rotation.y = lerp_angle(rotation.y, atan2(-d.x, -d.z), 1.0 - exp(-8.0 * delta))
