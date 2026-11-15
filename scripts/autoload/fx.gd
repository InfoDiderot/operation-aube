extends Node
## Autoload « Fx » : effets visuels légers (impacts, sang, traçantes, explosions, fumée).
## Tout est fait en CPUParticles3D + primitives pour rester compatible avec tous les rendus.

const MAX_HOLES := 80

var _mat_cache: Dictionary = {}
var _holes: Array = []
var _fade_curve: Curve
var _smoke_curve: Curve


func _ready() -> void:
	_fade_curve = Curve.new()
	_fade_curve.add_point(Vector2(0.0, 1.0))
	_fade_curve.add_point(Vector2(0.7, 0.8))
	_fade_curve.add_point(Vector2(1.0, 0.0))
	_smoke_curve = Curve.new()
	_smoke_curve.add_point(Vector2(0.0, 0.3))
	_smoke_curve.add_point(Vector2(0.4, 1.0))
	_smoke_curve.add_point(Vector2(1.0, 0.0))


## À appeler au chargement d'une mission (les anciens nœuds ont été libérés).
func reset() -> void:
	_holes.clear()


func _scene() -> Node3D:
	return get_tree().current_scene as Node3D


func flat_mat(color: Color, additive := false, unshaded := true) -> StandardMaterial3D:
	var key := "%s|%s|%s" % [color.to_html(), additive, unshaded]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_cache[key] = m
	return m


func _particle_mat(glow: bool) -> StandardMaterial3D:
	var key := "particle|%s" % glow
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 1.0
	if glow:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_cache[key] = m
	return m


func _smoke_mat() -> StandardMaterial3D:
	if _mat_cache.has("smoke"):
		return _mat_cache["smoke"]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat_cache["smoke"] = m
	return m


## Gerbe de particules ponctuelle (se détruit seule).
func burst(pos: Vector3, dir: Vector3, color: Color, amount: int, speed: float, lifetime: float,
		size: float, spread_deg := 40.0, gravity := -9.8, glow := false, smoke := false) -> void:
	var root := _scene()
	if root == null:
		return
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = maxi(amount, 1)
	p.lifetime = lifetime
	p.explosiveness = 0.95
	p.lifetime_randomness = 0.4
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE * size
	mesh.material = _smoke_mat() if smoke else _particle_mat(glow)
	p.mesh = mesh
	p.direction = dir if dir.length() > 0.01 else Vector3.UP
	p.spread = spread_deg
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector3(0.0, gravity, 0.0)
	p.damping_min = 1.0
	p.damping_max = 3.0
	p.angular_velocity_min = -180.0
	p.angular_velocity_max = 180.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	p.scale_amount_curve = _fade_curve
	p.color = color
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(lifetime + 0.5, false).timeout.connect(p.queue_free)


func impact(pos: Vector3, normal: Vector3) -> void:
	Sfx.play_at("impact", pos, -10.0, 40.0)
	burst(pos + normal * 0.02, normal, Color(0.55, 0.5, 0.42), 8, 3.5, 0.6, 0.06, 35.0, -6.0)
	burst(pos, normal, Color(1.0, 0.8, 0.4), 3, 6.0, 0.15, 0.025, 50.0, -9.0, true)
	_hole(pos, normal)


func blood(pos: Vector3, dir: Vector3) -> void:
	burst(pos, dir, Color(0.45, 0.03, 0.03), 10, 3.0, 0.5, 0.05, 45.0, -9.0)


func _hole(pos: Vector3, normal: Vector3) -> void:
	var root := _scene()
	if root == null:
		return
	var m := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.09, 0.09)
	m.mesh = q
	m.material_override = flat_mat(Color(0.08, 0.07, 0.06))
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(m)
	var up := Vector3.UP if absf(normal.y) < 0.95 else Vector3.RIGHT
	var p := pos + normal * 0.012
	m.look_at_from_position(p, p - normal, up)
	_holes.append(m)
	if _holes.size() > MAX_HOLES:
		var old: Variant = _holes.pop_front()
		if is_instance_valid(old):
			(old as Node).queue_free()


## Traçante qui file de `from` à `to` (~420 m/s).
func tracer(from: Vector3, to: Vector3, color := Color(1.0, 0.85, 0.55)) -> void:
	var root := _scene()
	if root == null:
		return
	var dist := from.distance_to(to)
	if dist < 1.5:
		return
	var seg := minf(3.0, dist * 0.4)
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(0.02, 0.02, seg)
	m.mesh = b
	m.material_override = flat_mat(color, true)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(m)
	var dir := (to - from) / dist
	var up := Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT
	var start := from + dir * seg * 0.5
	var end := to - dir * seg * 0.5
	m.look_at_from_position(start, start + dir, up)
	var tw := m.create_tween()
	tw.tween_property(m, "global_position", end, maxf(0.02, (dist - seg) / 420.0))
	tw.tween_callback(m.queue_free)


func muzzle_flash(pos: Vector3) -> void:
	var root := _scene()
	if root == null:
		return
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.7, 0.35)
	l.light_energy = 3.0
	l.omni_range = 4.0
	var s := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.1
	sm.height = 0.2
	sm.radial_segments = 6
	sm.rings = 3
	s.mesh = sm
	s.material_override = flat_mat(Color(1.0, 0.65, 0.25), true)
	root.add_child(l)
	root.add_child(s)
	l.global_position = pos
	s.global_position = pos
	get_tree().create_timer(0.05, false).timeout.connect(l.queue_free)
	get_tree().create_timer(0.05, false).timeout.connect(s.queue_free)


func explosion(pos: Vector3, scale := 1.0) -> void:
	var root := _scene()
	if root == null:
		return
	burst(pos + Vector3.UP * 0.3, Vector3.UP, Color(1.0, 0.55, 0.15), int(30 * scale), 9.0 * scale, 0.5, 0.35 * scale, 70.0, -2.0, true)
	burst(pos + Vector3.UP * 0.5, Vector3.UP, Color(0.25, 0.24, 0.22, 0.7), int(24 * scale), 4.0 * scale, 2.6, 0.9 * scale, 50.0, 0.6, false, true)
	burst(pos, Vector3.UP, Color(0.3, 0.25, 0.18), int(20 * scale), 12.0 * scale, 1.4, 0.12, 60.0, -12.0)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.6, 0.3)
	l.light_energy = 8.0 * scale
	l.omni_range = 18.0 * scale
	root.add_child(l)
	l.global_position = pos + Vector3.UP
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, 0.5)
	tw.tween_callback(l.queue_free)
	var scorch := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(3.0, 3.0) * scale
	scorch.mesh = q
	scorch.material_override = flat_mat(Color(0.1, 0.09, 0.08))
	scorch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(scorch)
	scorch.global_position = Vector3(pos.x, 0.03, pos.z)
	scorch.rotation = Vector3(-PI / 2.0, randf() * TAU, 0.0)
	Sfx.play_at("explosion", pos, 6.0, 300.0)
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player and player.has_method("add_shake"):
		var d := player.global_position.distance_to(pos)
		if d < 35.0:
			player.call("add_shake", clampf(1.2 - d / 25.0, 0.1, 1.0) * scale)


## Colonne de fumée permanente (maison en feu, signal de ralliement…).
func smoke_column(parent: Node3D, pos: Vector3, color := Color(0.3, 0.3, 0.3), scale := 1.0, fire := false) -> Node3D:
	var holder := Node3D.new()
	parent.add_child(holder)
	holder.position = pos
	var p := CPUParticles3D.new()
	p.amount = 28
	p.lifetime = 7.0
	p.preprocess = 7.0
	var mesh := SphereMesh.new()
	mesh.radius = 0.6 * scale
	mesh.height = 1.1 * scale
	mesh.radial_segments = 6
	mesh.rings = 3
	mesh.material = _smoke_mat()
	p.mesh = mesh
	p.direction = Vector3.UP
	p.spread = 12.0
	p.initial_velocity_min = 1.2 * scale
	p.initial_velocity_max = 2.2 * scale
	p.gravity = Vector3(0.35, 0.25, 0.1)
	p.angular_velocity_min = -30.0
	p.angular_velocity_max = 30.0
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.5
	p.scale_amount_curve = _smoke_curve
	p.color = Color(color, 0.55)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(p)
	if fire:
		var f := CPUParticles3D.new()
		f.amount = 24
		f.lifetime = 0.9
		var fm := BoxMesh.new()
		fm.size = Vector3.ONE * 0.45 * scale
		fm.material = _particle_mat(true)
		f.mesh = fm
		f.direction = Vector3.UP
		f.spread = 20.0
		f.initial_velocity_min = 1.0
		f.initial_velocity_max = 2.5
		f.gravity = Vector3(0, 1.0, 0)
		f.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		f.emission_sphere_radius = 0.8 * scale
		f.scale_amount_curve = _fade_curve
		f.color = Color(1.0, 0.45, 0.12)
		holder.add_child(f)
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.5, 0.2)
		l.light_energy = 1.5
		l.omni_range = 7.0 * scale
		l.position = Vector3.UP
		holder.add_child(l)
	return holder
