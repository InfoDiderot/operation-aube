class_name AmmoPickup
extends Area3D
## Caisse de munitions lâchée par un ennemi : ramassage automatique au contact.

var _mesh: MeshInstance3D
var _t := randf() * TAU


func _ready() -> void:
	collision_layer = 0
	collision_mask = Game.LAYER_PLAYER
	var cs := CollisionShape3D.new()
	var s := SphereShape3D.new()
	s.radius = 1.1
	cs.shape = s
	add_child(cs)
	_mesh = MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(0.36, 0.2, 0.24)
	_mesh.mesh = b
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.42, 0.4, 0.22)
	m.emission_enabled = true
	m.emission = Color(0.35, 0.3, 0.1)
	m.emission_energy_multiplier = 0.4
	_mesh.material_override = m
	add_child(_mesh)
	body_entered.connect(_on_body)


func _process(delta: float) -> void:
	_t += delta
	_mesh.rotation.y = _t
	_mesh.position.y = 0.05 + sin(_t * 2.0) * 0.05


func _on_body(b: Node3D) -> void:
	if b is Player and not (b as Player).dead:
		(b as Player).add_ammo()
		queue_free()
