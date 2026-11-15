class_name Grenade
extends RigidBody3D
## Grenade à fragmentation (joueur) ou à manche (ennemi). Dégâts dégressifs, réduits derrière un mur.

const FUSE := 3.2
const RADIUS := 7.0
const DAMAGE := 160.0

var from_player := true
var _t := FUSE
var _done := false


func _ready() -> void:
	add_to_group("grenade")
	collision_layer = 0
	collision_mask = Game.LAYER_WORLD
	mass = 0.6
	continuous_cd = true
	angular_damp = 1.5
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.3
	pm.friction = 0.8
	physics_material_override = pm
	var shape := CollisionShape3D.new()
	var s := SphereShape3D.new()
	s.radius = 0.07
	shape.shape = s
	add_child(shape)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.33, 0.2) if from_player else Color(0.35, 0.36, 0.33)
	var mi := MeshInstance3D.new()
	if from_player:
		var sm := SphereMesh.new()
		sm.radius = 0.06
		sm.height = 0.13
		sm.radial_segments = 8
		sm.rings = 4
		mi.mesh = sm
	else:
		var cm := CylinderMesh.new()
		cm.top_radius = 0.04
		cm.bottom_radius = 0.04
		cm.height = 0.35
		cm.radial_segments = 6
		mi.mesh = cm
	mi.material_override = mat
	add_child(mi)
	contact_monitor = true
	max_contacts_reported = 1
	body_entered.connect(func(_b: Node) -> void: Sfx.play_at("bounce", global_position, -6.0, 30.0))


func _physics_process(delta: float) -> void:
	_t -= delta
	if _t <= 0.0 and not _done:
		_explode()


func is_live_threat() -> bool:
	return not from_player and not _done


func _explode() -> void:
	_done = true
	Fx.explosion(global_position, 1.0)
	var space := get_world_3d().direct_space_state
	var player := get_tree().get_first_node_in_group("player") as Player
	for e in get_tree().get_nodes_in_group("enemy"):
		var enemy := e as Enemy
		var dmg := _damage_to(enemy, space)
		if dmg > 0.0 and enemy.take_explosion(dmg, global_position) and from_player and player:
			player.register_hit(true, false)
	if player:
		var pd := _damage_to(player, space)
		if pd > 0.0:
			pd *= 0.6 if from_player else Game.enemy_damage_mult()
			player.take_damage(pd, global_position)
	Game.make_noise(global_position, 60.0)
	queue_free()


func _damage_to(target: Node3D, space: PhysicsDirectSpaceState3D) -> float:
	var center := target.global_position + Vector3.UP
	var d := global_position.distance_to(center)
	if d > RADIUS:
		return 0.0
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.2, center, Game.LAYER_WORLD)
	var blocked := not space.intersect_ray(q).is_empty()
	return DAMAGE * pow(1.0 - d / RADIUS, 1.3) * (0.25 if blocked else 1.0)
