class_name Enemy
extends CharacterBody3D
## Soldat ennemi.
## Perception : vue (cône + ligne de visée) et ouïe (Game.noise_made).
## États : IDLE / PATROL -> ALERT -> COMBAT <-> COVER -> DEAD.
## Équité : temps de réaction avant le 1er tir et premiers tirs volontairement ratés.

signal died(enemy: Enemy)

enum State { IDLE, PATROL, ALERT, COMBAT, COVER, DEAD }

const KINDS := {
	"rifle": {"burst": Vector2i(1, 1), "interval": 0.0, "pause": Vector2(1.3, 2.3), "damage": 24.0,
		"acc": 0.5, "range": 60.0, "sound": "enemy_rifle", "engage": 35.0, "misses": 1},
	"smg": {"burst": Vector2i(4, 6), "interval": 0.1, "pause": Vector2(1.0, 1.7), "damage": 10.0,
		"acc": 0.3, "range": 30.0, "sound": "enemy_smg", "engage": 18.0, "misses": 3},
	"mg": {"burst": Vector2i(7, 11), "interval": 0.08, "pause": Vector2(1.3, 2.0), "damage": 11.0,
		"acc": 0.24, "range": 70.0, "sound": "enemy_mg", "engage": 90.0, "misses": 4},
}
const VIEW_DIST := 55.0
const FOV_DOT := 0.42        # cos(65°)
const WALK := 2.2
const RUN := 4.2
const GRAVITY := 15.0

var kind := "rifle"
var zone := ""
var health := 100.0
var state := State.IDLE
var patrol_points: Array[Vector3] = []
var static_post := false     # mitrailleur : ne quitte pas son poste
var hunter := false          # contre-attaque : connaît toujours la position du joueur

var _cfg: Dictionary
var _player: Player
var _target: Node3D          # cible actuelle : le joueur ou un coéquipier
var _agent: NavigationAgent3D
var _shape: CollisionShape3D
var _capsule: CapsuleShape3D
var model: SoldierModel
var _last_known := Vector3.ZERO
var _can_see := false
var _sight_timer := 0.0
var _reaction := 0.0
var _lost_time := 0.0
var _shot_cd := 0.0
var _burst_left := 0
var _shots_since_spot := 0
var _repath := 0.0
var _move_target := Vector3.INF
var _strafe_timer := 0.0
var _cover_node: Node3D = null
var _cover_wait := 0.0
var _used_cover := false
var _grenade_cd := 8.0
var _look_timer := 0.0
var _target_yaw := 0.0
var _idle_yaw := 0.0
var _alert_time := 0.0
var _crouch := 0.0
var _crouch_target := 0.0
static var _last_grenade_ms := -100000


func _ready() -> void:
	_cfg = KINDS.get(kind, KINDS["rifle"])
	add_to_group("enemy")
	collision_layer = Game.LAYER_ENEMY
	collision_mask = Game.LAYER_WORLD | Game.LAYER_PLAYER | Game.LAYER_ENEMY | Game.LAYER_ALLY
	_capsule = CapsuleShape3D.new()
	_capsule.radius = 0.35
	_capsule.height = 1.8
	_shape = CollisionShape3D.new()
	_shape.shape = _capsule
	_shape.position.y = 0.9
	add_child(_shape)
	_agent = NavigationAgent3D.new()
	_agent.path_desired_distance = 0.7
	_agent.target_desired_distance = 1.0
	_agent.radius = 0.4
	_agent.height = 1.8
	add_child(_agent)
	model = SoldierModel.new()
	model.faction = "axis"
	model.weapon_kind = kind
	add_child(model)
	_idle_yaw = rotation.y
	_target_yaw = rotation.y
	state = State.PATROL if not patrol_points.is_empty() else State.IDLE
	Game.noise_made.connect(_on_noise)


func _get_player() -> Player:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Player
	return _player


# --- Dégâts ----------------------------------------------------------------------

## Appelé par le tir du joueur. Retourne {hit, killed, headshot}.
func take_bullet(dmg: float, point: Vector3, head_mult: float, dir := Vector3.ZERO) -> Dictionary:
	if state == State.DEAD:
		return {"hit": false}
	var headshot := point.y > model.neck_height() + 0.02
	var d := dmg * (head_mult if headshot else 1.0)
	if point.y - global_position.y < 0.8:
		d *= 0.8   # jambes
	health -= d
	Fx.blood(point, -dir if dir != Vector3.ZERO else Vector3.UP)
	Sfx.play_at("body_hit", point, 0.0, 50.0)
	if health <= 0.0:
		_die(dir)
		return {"hit": true, "killed": true, "headshot": headshot}
	if randf() < 0.5:
		model.play_action("Hit_A" if randf() < 0.5 else "Hit_B")
	var p := _get_player()
	if p:
		_alert_to(p.global_position, true)
	return {"hit": true, "killed": false, "headshot": headshot}


## Appelé par un coéquipier : dégâts sans statistiques joueur, l'ennemi riposte vers lui.
func take_ally_hit(dmg: float, from_pos: Vector3) -> void:
	if state == State.DEAD:
		return
	health -= dmg
	Fx.blood(global_position + Vector3.UP * 1.2, (from_pos - global_position).normalized())
	if health <= 0.0:
		_die((global_position - from_pos).normalized())
		return
	_alert_to(from_pos, true)


## Appelé par les grenades. Retourne true si l'ennemi meurt.
func take_explosion(dmg: float, origin: Vector3) -> bool:
	if state == State.DEAD:
		return false
	health -= dmg
	if health <= 0.0:
		var away := global_position - origin
		away.y = 0.0
		_die(away.normalized())
		return true
	_alert_to(origin, false)
	return false


func is_dead() -> bool:
	return state == State.DEAD


func _die(dir: Vector3) -> void:
	state = State.DEAD
	collision_layer = 0
	collision_mask = Game.LAYER_WORLD
	_release_cover()
	velocity = Vector3.ZERO
	# Le corps tombe dans le sens de l'impact : on oriente le soldat dos au tir
	if dir != Vector3.ZERO:
		rotation.y = atan2(dir.x, dir.z)
	model.play_death()
	if randf() < 0.6:
		var pick := AmmoPickup.new()
		get_parent().add_child(pick)
		pick.global_position = global_position + Vector3(randf_range(-0.6, 0.6), 0.25, randf_range(-0.6, 0.6))
	died.emit(self)


# --- Perception ----------------------------------------------------------------

## Cherche une cible visible (joueur prioritaire à distance égale, sinon coéquipier).
## Met à jour _target ; retourne true si une cible est vue.
func _check_sight() -> bool:
	var best: Node3D = null
	var best_score := INF
	var candidates: Array = [_get_player()]
	candidates.append_array(get_tree().get_nodes_in_group("ally"))
	for c in candidates:
		var t := c as Node3D
		if t == null or t.get("dead"):
			continue
		var d := _sight_distance(t)
		if d < 0.0:
			continue
		var score := d * (0.8 if t is Player else 1.0)
		if score < best_score:
			best = t
			best_score = score
	if best:
		_target = best
	return best != null


## Distance si la cible est visible, -1 sinon.
func _sight_distance(t: Node3D) -> float:
	var eye := global_position + Vector3.UP * lerpf(1.6, 1.05, _crouch)
	var crouch_t: float = t.get("crouch_t")
	var aim := t.global_position + Vector3.UP * lerpf(1.45, 0.95, crouch_t)
	var to := aim - eye
	var dist := to.length()
	var calm := state == State.IDLE or state == State.PATROL
	if dist > (VIEW_DIST if calm else VIEW_DIST * 1.6):
		return -1.0
	if calm:
		var fwd := -global_transform.basis.z
		if fwd.dot(to / dist) < FOV_DOT and dist > 4.0:
			return -1.0
		if t.get("crouching") and dist > 28.0:
			return -1.0
	var q := PhysicsRayQueryParameters3D.create(eye, aim,
		Game.LAYER_WORLD | Game.LAYER_PLAYER | Game.LAYER_ALLY, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return dist if not hit.is_empty() and hit["collider"] == t else -1.0


func _on_noise(pos: Vector3, radius: float) -> void:
	if state == State.DEAD or not is_inside_tree():
		return
	if global_position.distance_to(pos) < radius and (state == State.IDLE or state == State.PATROL):
		_alert_to(pos + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3)), false)


func _alert_to(pos: Vector3, combat: bool) -> void:
	if state == State.DEAD:
		return
	_last_known = pos
	if combat:
		if state != State.COMBAT and state != State.COVER:
			_reaction = randf_range(0.25, 0.45)
			_shots_since_spot = 0
		if state != State.COVER:
			state = State.COMBAT
	elif state == State.IDLE or state == State.PATROL:
		state = State.ALERT
		_alert_time = 0.0
		_repath = 0.0


## Le joueur vient d'entrer dans le champ de vision.
func _on_spotted() -> void:
	var calm := state == State.IDLE or state == State.PATROL or state == State.ALERT
	_reaction = randf_range(0.55, 0.9) if calm else randf_range(0.25, 0.45)
	_reaction *= [1.4, 1.0, 0.8][Game.difficulty]
	if calm:
		_shots_since_spot = 0
		for e in get_tree().get_nodes_in_group("enemy"):
			var other := e as Enemy
			if other != self and other.global_position.distance_to(global_position) < 22.0:
				other._alert_to(_last_known, false)
	if state != State.COVER:
		state = State.COMBAT


# --- Boucle ------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	if state == State.DEAD:
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return
	var p := _get_player()
	_sight_timer -= delta
	if _sight_timer <= 0.0:
		_sight_timer = 0.15 + randf() * 0.1
		var seen := _check_sight()
		if seen and not _can_see:
			_last_known = _target.global_position
			_on_spotted()
		_can_see = seen
	if _can_see and _target:
		_last_known = _target.global_position
		_lost_time = 0.0
	else:
		_lost_time += delta
		if hunter and p and not p.dead:
			_last_known = p.global_position
	_grenade_cd -= delta
	_shot_cd -= delta

	match state:
		State.IDLE:
			_do_idle(delta)
		State.PATROL:
			_do_patrol(delta)
		State.ALERT:
			_do_alert(delta)
		State.COMBAT:
			_do_combat(delta)
		State.COVER:
			_do_cover(delta)
	move_and_slide()
	_animate(delta)


func _stop() -> void:
	velocity.x = 0.0
	velocity.z = 0.0


func _do_idle(delta: float) -> void:
	_stop()
	_look_timer -= delta
	if _look_timer <= 0.0:
		_look_timer = randf_range(2.0, 5.0)
		_target_yaw = _idle_yaw + randf_range(-0.9, 0.9)
	rotation.y = lerp_angle(rotation.y, _target_yaw, 1.0 - exp(-2.0 * delta))


func _do_patrol(delta: float) -> void:
	var target := patrol_points[_patrol_index()]
	if global_position.distance_to(target) < 1.2:
		_stop()
		_look_timer -= delta
		if _look_timer <= 0.0:
			_look_timer = randf_range(1.5, 3.0)
			set_meta("patrol_i", (_patrol_index() + 1) % patrol_points.size())
		return
	_nav_to(target, delta)
	_follow_nav(WALK, true, delta)


func _patrol_index() -> int:
	return get_meta("patrol_i", 0)


func _do_alert(delta: float) -> void:
	_alert_time += delta
	if global_position.distance_to(_last_known) > 2.0 and _alert_time < 20.0:
		_nav_to(_last_known, delta)
		_follow_nav(3.0, true, delta)
	else:
		_stop()
		_look_timer -= delta
		if _look_timer <= 0.0:
			_look_timer = randf_range(1.0, 2.5)
			_target_yaw = rotation.y + randf_range(-1.5, 1.5)
		rotation.y = lerp_angle(rotation.y, _target_yaw, 1.0 - exp(-3.0 * delta))
		if _alert_time > 14.0:
			_idle_yaw = rotation.y
			state = State.IDLE


func _do_combat(delta: float) -> void:
	var p := _target if _target else _get_player()
	if p == null or p.get("dead"):
		_stop()
		return
	if _can_see:
		_face_towards(p.global_position, delta, 8.0)
		_reaction -= delta
		if _reaction <= 0.0:
			_try_fire()
		if static_post:
			_stop()
		else:
			var dist := global_position.distance_to(p.global_position)
			_strafe_timer -= delta
			if dist > float(_cfg["engage"]):
				_nav_to(p.global_position, delta)
				_follow_nav(RUN * 0.8, false, delta)
			else:
				if _strafe_timer <= 0.0:
					_strafe_timer = randf_range(1.5, 3.5)
					if randf() < 0.55:
						var right := global_transform.basis.x
						_set_nav(global_position + right * randf_range(-3.5, 3.5))
					else:
						_set_nav(global_position)
				_follow_nav(WALK * 1.2, false, delta)
			if health < 55.0 and not _used_cover:
				_seek_cover()
	else:
		if static_post:
			_stop()
			_face_towards(_last_known, delta, 3.0)
			return
		var d_last := global_position.distance_to(_last_known)
		if _lost_time > 3.0 and _grenade_cd <= 0.0 and d_last < 26.0 and d_last > 7.0 \
				and Time.get_ticks_msec() - _last_grenade_ms > 8000 and randf() < 0.5:
			_throw_grenade(_last_known)
		if _lost_time > 1.2:
			_nav_to(_last_known, delta)
			var arrived := _follow_nav(RUN, true, delta)
			if arrived and _lost_time > 10.0 and not hunter:
				state = State.ALERT
				_alert_time = 0.0
		else:
			_stop()


func _do_cover(delta: float) -> void:
	if _cover_node == null or not is_instance_valid(_cover_node):
		state = State.COMBAT
		return
	var cpos := _cover_node.global_position
	var flat := Vector2(global_position.x - cpos.x, global_position.z - cpos.z).length()
	if flat > 0.9:
		_nav_to(cpos, delta)
		if _follow_nav(RUN, true, delta):
			_set_nav(global_position)
			_cover_wait -= delta * 0.5
	else:
		_stop()
		_crouch_target = 1.0
		_cover_wait -= delta
		_face_towards(_last_known, delta, 4.0)
		if _can_see:
			_reaction -= delta
			if _reaction <= 0.0:
				_try_fire()
	if _cover_wait <= 0.0:
		_crouch_target = 0.0
		health = minf(health + 15.0, 100.0)
		_release_cover()
		state = State.COMBAT


func _seek_cover() -> void:
	var threat := _last_known
	var best: Node3D = null
	var best_d := 14.0
	var space := get_world_3d().direct_space_state
	for c in get_tree().get_nodes_in_group("cover"):
		var node := c as Node3D
		var d := global_position.distance_to(node.global_position)
		if d > best_d or node.get_meta("taken", false):
			continue
		# La position doit masquer le joueur (rayon à hauteur d'homme accroupi)
		var q := PhysicsRayQueryParameters3D.create(node.global_position + Vector3.UP * 0.8,
			threat + Vector3.UP * 1.4, Game.LAYER_WORLD)
		if space.intersect_ray(q).is_empty():
			continue
		best = node
		best_d = d
	_used_cover = true
	if best:
		best.set_meta("taken", true)
		_cover_node = best
		_cover_wait = randf_range(3.0, 5.0)
		state = State.COVER
		_set_nav(best.global_position)


func _release_cover() -> void:
	if _cover_node and is_instance_valid(_cover_node):
		_cover_node.set_meta("taken", false)
	_cover_node = null


# --- Tir -------------------------------------------------------------------------

func _try_fire() -> void:
	if _shot_cd > 0.0:
		return
	var burst: Vector2i = _cfg["burst"]
	var pause: Vector2 = _cfg["pause"]
	if burst.y <= 1:
		_shoot_once()
		_shot_cd = randf_range(pause.x, pause.y)
		return
	if _burst_left <= 0:
		_burst_left = randi_range(burst.x, burst.y)
	_shoot_once()
	_burst_left -= 1
	_shot_cd = float(_cfg["interval"]) if _burst_left > 0 else randf_range(pause.x, pause.y)


func _shoot_once() -> void:
	var p := _target if _target else _get_player()
	if p == null:
		return
	var muzzle := model.gun_tip.global_position
	var target := p.global_position + Vector3.UP * lerpf(1.3, 0.85, float(p.get("crouch_t")))
	var dist := muzzle.distance_to(target)
	var acc := float(_cfg["acc"]) * Game.enemy_accuracy_mult()
	acc *= clampf(1.25 - dist / float(_cfg["range"]), 0.2, 1.0)
	var tv: Vector3 = p.get("velocity")
	if Vector2(tv.x, tv.z).length() > 3.0:
		acc *= 0.6
	if p.get("crouching"):
		acc *= 0.8
	if _shots_since_spot < int(_cfg["misses"]):
		acc = 0.0   # premiers tirs volontairement ratés : le joueur a le temps de réagir
	_shots_since_spot += 1
	Sfx.play_at(_cfg["sound"], muzzle, 2.0)
	Fx.muzzle_flash(muzzle)
	model.play_shoot()
	if randf() < acc:
		p.call("take_damage", float(_cfg["damage"]) * Game.enemy_damage_mult(), global_position)
		Fx.tracer(muzzle, target)
		return
	var offset := Vector3(randf_range(-1, 1), randf_range(-0.5, 0.8), randf_range(-1, 1)).normalized() * randf_range(0.6, 2.2)
	var dir := (target + offset - muzzle).normalized()
	var q := PhysicsRayQueryParameters3D.create(muzzle, muzzle + dir * (dist + 40.0), Game.LAYER_WORLD, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var end := muzzle + dir * (dist + 40.0)
	if not hit.is_empty():
		end = hit["position"]
		Fx.impact(end, hit["normal"])
	Fx.tracer(muzzle, end)
	# Sifflement si la balle frôle le joueur
	var pl := _get_player()
	var ear := pl.global_position + Vector3.UP * 1.5 if pl else target
	var closest := Geometry3D.get_closest_point_to_segment(ear, muzzle, end)
	if closest.distance_to(ear) < 2.0:
		Sfx.play("whiz", -10.0, 0.2)


func _throw_grenade(target: Vector3) -> void:
	_grenade_cd = randf_range(14.0, 22.0)
	_last_grenade_ms = Time.get_ticks_msec()
	model.play_action("Throw")
	var g := Grenade.new()
	g.from_player = false
	get_parent().add_child(g)
	g.global_position = global_position + Vector3.UP * 1.8 - global_transform.basis.z * 0.4
	var aim := target + Vector3(randf_range(-1.5, 1.5), 0.0, randf_range(-1.5, 1.5))
	var t := 1.2
	var d := aim - g.global_position
	var grav := float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	g.linear_velocity = Vector3(d.x / t, (d.y + 0.5 * grav * t * t) / t, d.z / t)
	g.add_collision_exception_with(self)


# --- Navigation -------------------------------------------------------------------

func _set_nav(pos: Vector3) -> void:
	_move_target = pos
	_agent.target_position = pos
	_repath = 0.5


func _nav_to(pos: Vector3, delta: float) -> void:
	_repath -= delta
	if _repath <= 0.0 or _move_target.distance_to(pos) > 2.0:
		_set_nav(pos)


## Avance le long du chemin ; retourne true une fois arrivé.
func _follow_nav(speed: float, face_move: bool, delta: float) -> bool:
	if _agent.is_navigation_finished():
		_stop()
		return true
	var next := _agent.get_next_path_position()
	var dir := next - global_position
	dir.y = 0.0
	if dir.length() < 0.05:
		_stop()
		return _agent.is_navigation_finished()
	dir = dir.normalized()
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	if face_move:
		_face_towards(global_position + dir, delta, 6.0)
	return false


func _face_towards(pos: Vector3, delta: float, rate: float) -> void:
	var d := pos - global_position
	if Vector2(d.x, d.z).length() < 0.01:
		return
	rotation.y = lerp_angle(rotation.y, atan2(-d.x, -d.z), 1.0 - exp(-rate * delta))


# --- Visuel ------------------------------------------------------------------------

func _animate(delta: float) -> void:
	if state != State.COVER:
		_crouch_target = 0.0
	_crouch = move_toward(_crouch, _crouch_target, delta * 4.0)
	_capsule.height = lerpf(1.8, 1.25, _crouch)
	_shape.position.y = _capsule.height / 2.0
	var spd := Vector2(velocity.x, velocity.z).length()
	# Repère local : la vitesse sert à la locomotion, l'arme est épaulée en combat
	var aim := 1.0 if (state == State.COMBAT or state == State.COVER) else 0.0
	model.set_motion(spd, aim, _crouch)
