class_name LevelBuilder
extends RefCounted
## Construit procéduralement le village normand (stylisé) : sol, routes, haies du bocage,
## maisons, église, place, site du canon de 88, point de ralliement, couvertures et navmesh.
## Matériaux procéduraux (Mats) ; végétation Quaternius en MultiMesh (Nature).
## Une grille d'occupation (1 m) empêche l'herbe de pousser dans les murs et sur les routes.
## Le nord est vers -Z. Zone jouable : x ∈ [-70, 70], z ∈ [-90, 110].

const C_GRASS_A := Color(0.33, 0.45, 0.2)
const C_GRASS_B := Color(0.42, 0.5, 0.24)
const C_ROAD := Color(0.47, 0.4, 0.3)
const C_COBBLE := Color(0.36, 0.35, 0.33)
const C_STONE := Color(0.74, 0.68, 0.57)
const C_STONE2 := Color(0.64, 0.6, 0.52)
const C_PLASTER := Color(0.86, 0.8, 0.68)
const C_BEAM := Color(0.3, 0.2, 0.12)
const C_ROOF := Color(0.47, 0.23, 0.16)
const C_SLATE := Color(0.3, 0.32, 0.36)
const C_WOOD := Color(0.42, 0.29, 0.17)
const C_DARK := Color(0.1, 0.09, 0.08)
const C_HEDGE := Color(0.2, 0.33, 0.13)
const C_LEAF := Color(0.26, 0.4, 0.15)
const C_LEAF2 := Color(0.33, 0.45, 0.17)
const C_SAND := Color(0.6, 0.53, 0.37)
const C_HAY := Color(0.78, 0.66, 0.35)
const C_FLAK := Color(0.5, 0.47, 0.33)
const C_BURNT := Color(0.16, 0.15, 0.14)
const C_OLIVE := Color(0.3, 0.33, 0.2)
const SHUTTERS := [Color(0.3, 0.42, 0.45), Color(0.32, 0.42, 0.28), Color(0.5, 0.25, 0.2)]

var root: Node3D
var nav: NavigationRegion3D
var flak: Node3D
var flak_barrel: Node3D
var _mats: Dictionary = {}
var rng := RandomNumberGenerator.new()
var nature := Nature.new()
var _blocked: Dictionary = {}     # Vector2i (cellule de 1 m) -> true
const C_FRAME := Color(0.82, 0.79, 0.72)
const C_GLASS := Color(0.12, 0.14, 0.16)
const TREES := ["NormalTree_1", "NormalTree_2", "NormalTree_3", "NormalTree_4", "NormalTree_5"]


func build(parent: Node3D) -> void:
	rng.seed = 1944
	root = parent
	nav = NavigationRegion3D.new()
	nav.name = "Navigation"
	var nm := NavigationMesh.new()
	nm.agent_radius = 0.5
	nm.agent_height = 2.0
	nm.agent_max_climb = 0.25
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = Game.LAYER_WORLD
	nm.filter_baking_aabb = AABB(Vector3(-72, -2, -92), Vector3(144, 10, 204))
	nav.navigation_mesh = nm
	root.add_child(nav)
	_ground()
	_bocage()
	_village()
	_flak_site()
	_rally_site()
	_north_fields()
	_bounds()
	_ground_cover()
	nature.flush(root, 70.0 if Game.quality > 0 else 45.0)
	nav.bake_navigation_mesh(false)


## Sol pavé ou chemin (pas sur pierre) : route, place, ruelles, intérieur du village.
static func is_paved(p: Vector3) -> bool:
	if absf(p.x) < 3.5 and p.z > -16.0 and p.z < 110.0:
		return true
	if absf(p.x) < 20.0 and p.z > -19.0 and p.z < 11.0:
		return true
	return p.x > -60.0 and p.x < 56.0 and p.z > -5.0 and p.z < 1.0


# --- Primitives -------------------------------------------------------------------

func mat(c: Color) -> StandardMaterial3D:
	if _mats.has(c):
		return _mats[c]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.92
	_mats[c] = m
	return m


func _vary(c: Color, amount := 0.06) -> Color:
	var k := rng.randf_range(-amount, amount)
	return Color(c.r + k, c.g + k, c.b + k * 0.6)


func _static(pos: Vector3, rot_y_deg := 0.0, parent: Node3D = null) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = Game.LAYER_WORLD
	body.collision_mask = 0
	body.position = pos
	body.rotation.y = deg_to_rad(rot_y_deg)
	(parent if parent else nav).add_child(body)
	return body


func _shape(body: Node3D, shape: Shape3D, pos := Vector3.ZERO, rot := Vector3.ZERO) -> void:
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = pos
	cs.rotation = rot
	body.add_child(cs)
	if shape is BoxShape3D:
		var sz := (shape as BoxShape3D).size
		if sz.x < 100.0 and sz.z < 100.0 and sz.y > 0.3:
			_mark_rect(cs.global_transform, sz)
	elif shape is CylinderShape3D:
		var o := cs.global_position
		_mark_disc(Vector2(o.x, o.z), (shape as CylinderShape3D).radius + 0.3)


func _mark_rect(xf: Transform3D, size: Vector3) -> void:
	var inv := xf.affine_inverse()
	var r := Vector2(size.x, size.z).length() * 0.5 + 0.5
	var o := xf.origin
	for x in range(floori(o.x - r), ceili(o.x + r) + 1):
		for z in range(floori(o.z - r), ceili(o.z + r) + 1):
			var lp := inv * Vector3(x + 0.5, o.y, z + 0.5)
			if absf(lp.x) < size.x * 0.5 + 0.4 and absf(lp.z) < size.z * 0.5 + 0.4:
				_blocked[Vector2i(x, z)] = true


func _mark_disc(c: Vector2, r: float) -> void:
	for x in range(floori(c.x - r), ceili(c.x + r) + 1):
		for z in range(floori(c.y - r), ceili(c.y + r) + 1):
			if Vector2(x + 0.5, z + 0.5).distance_to(c) < r:
				_blocked[Vector2i(x, z)] = true


func is_blocked(p: Vector3) -> bool:
	return _blocked.has(Vector2i(floori(p.x), floori(p.z)))


## `c` : une Color (matériau uni) ou un Material (procédural).
func mesh(m: Mesh, pos: Vector3, c: Variant, rot_deg := Vector3.ZERO, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = c if c is Material else mat(c)
	mi.position = pos
	mi.rotation_degrees = rot_deg
	(parent if parent else nav).add_child(mi)
	return mi


func boxm(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


## Bloc avec collision optionnelle.
func box(pos: Vector3, size: Vector3, c: Variant, rot_y := 0.0, collide := true, parent: Node3D = null) -> Node3D:
	if not collide:
		return mesh(boxm(size), pos, c, Vector3(0, rot_y, 0), parent)
	var body := _static(pos, rot_y, parent)
	var s := BoxShape3D.new()
	s.size = size
	_shape(body, s)
	mesh(boxm(size), Vector3.ZERO, c, Vector3.ZERO, body)
	return body


func cyl(pos: Vector3, radius: float, height: float, c: Variant, sides := 8, collide := true, top_radius := -1.0) -> Node3D:
	var cm := CylinderMesh.new()
	cm.top_radius = radius if top_radius < 0.0 else top_radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = sides
	cm.rings = 1
	if not collide:
		return mesh(cm, pos, c)
	var body := _static(pos)
	var s := CylinderShape3D.new()
	s.radius = radius
	s.height = height
	_shape(body, s)
	mesh(cm, Vector3.ZERO, c, Vector3.ZERO, body)
	return body


func blob(pos: Vector3, radius: float, height: float, c: Color, parent: Node3D = null) -> MeshInstance3D:
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = height
	sm.radial_segments = 7
	sm.rings = 4
	return mesh(sm, pos, c, Vector3(0, rng.randf_range(0, 360), 0), parent)


## Point de couverture utilisé par l'IA (groupe « cover »).
func cover(pos: Vector3) -> void:
	var m := Marker3D.new()
	m.position = Vector3(pos.x, 0.0, pos.z)
	m.add_to_group("cover")
	root.add_child(m)


# --- Sol & routes -----------------------------------------------------------------

func _ground() -> void:
	var body := _static(Vector3(0, -0.5, 10))
	var s := BoxShape3D.new()
	s.size = Vector3(400, 1, 400)
	_shape(body, s)
	var pm := PlaneMesh.new()
	pm.size = Vector2(400, 400)
	var gi := MeshInstance3D.new()
	gi.mesh = pm
	gi.material_override = Mats.ground()
	gi.position = Vector3(0, 0.5, 0)
	body.add_child(gi)
	# Route principale (sud -> place), place pavée, ruelles est/ouest
	box(Vector3(0, 0.012, 47.5), Vector3(6, 0.02, 125), Mats.dirt_road(), 0.0, false)
	box(Vector3(-1.6, 0.016, 47.5), Vector3(0.45, 0.02, 125), Color(0.3, 0.25, 0.19), 0.0, false)
	box(Vector3(1.6, 0.016, 47.5), Vector3(0.45, 0.02, 125), Color(0.3, 0.25, 0.19), 0.0, false)
	box(Vector3(0, 0.014, -2), Vector3(40, 0.02, 26), Mats.cobble(), 0.0, false)
	box(Vector3(0, 0.014, -17), Vector3(14, 0.02, 4), Mats.cobble(), 0.0, false)
	box(Vector3(38, 0.013, -2), Vector3(36, 0.02, 5), Mats.dirt_road(), 0.0, false)
	box(Vector3(-40, 0.013, -2), Vector3(40, 0.02, 5), Mats.dirt_road(), 0.0, false)
	# Poteaux télégraphiques le long de la route
	for z in range(100, 40, -20):
		cyl(Vector3(4.2, 3.5, z), 0.1, 7.0, C_WOOD, 5, false)
		box(Vector3(4.2, 6.6, z), Vector3(1.4, 0.1, 0.1), C_WOOD, 0.0, false)


# --- Bocage (zone de départ) ---------------------------------------------------------

## Haie du bocage avec trouées (en mètres le long du segment) ; ajoute des couvertures.
func hedge(a: Vector3, b: Vector3, gaps: Array = [], h := 2.4) -> void:
	var dir := b - a
	var length := dir.length()
	dir = dir / length
	var yaw := rad_to_deg(atan2(dir.x, dir.z))
	var side := Vector3(dir.z, 0, -dir.x)
	var cuts: Array[float] = [0.0]
	for g: Array in gaps:
		cuts.append(float(g[0]))
		cuts.append(float(g[1]))
	cuts.append(length)
	for i in range(0, cuts.size(), 2):
		var s0 := cuts[i]
		var s1 := cuts[i + 1]
		if s1 - s0 < 0.5:
			continue
		var mid := a + dir * (s0 + s1) * 0.5
		# Noyau (collision + masque de vue), recouvert de buissons
		var core := box(mid + Vector3.UP * (h - 0.3) * 0.5, Vector3(1.3, h - 0.3, s1 - s0), Color(0.15, 0.24, 0.09), yaw)
		# Collision pleine hauteur, mais le noyau visible reste sous la cime des buissons
		var core_mesh := core.get_child(core.get_child_count() - 1) as Node3D
		core_mesh.scale = Vector3(0.8, 0.62, 1.0)
		core_mesh.position.y = -(h - 0.3) * 0.19
		var t := s0 + 0.6
		var k := 0
		while t < s1 - 0.4:
			var p := a + dir * t
			for sd: float in [-0.35, 0.35]:
				var bp := p + side * (sd + rng.randf_range(-0.15, 0.15))
				var kind := "Bush_Large" if rng.randf() < 0.85 else "Bush_Large_Flowers"
				nature.add_at(kind, bp, rng.randf_range(1.75, 2.15), rng.randf() * TAU)
			if rng.randf() < 0.35:
				nature.add_at("Plant_%d" % (1 + rng.randi() % 2), p + side * rng.randf_range(-1.1, 1.1),
					rng.randf_range(0.9, 1.3), rng.randf() * TAU)
			if k % 3 == 1:
				cover(p + side * 1.4)
				cover(p - side * 1.4)
			t += 1.5
			k += 1
		if rng.randf() < 0.5:
			tree(a + dir * rng.randf_range(s0, s1), rng.randf_range(0.9, 1.3))


## Arbre Quaternius ; seul le tronc a une collision (balles et regards passent dans le feuillage).
func tree(pos: Vector3, s := 1.0, kind := "") -> void:
	if kind == "":
		kind = TREES[rng.randi() % TREES.size()]
	nature.add_at(kind, pos, s * rng.randf_range(0.95, 1.15), rng.randf() * TAU)
	var body := _static(pos + Vector3.UP * 1.5 * s)
	var cs := CylinderShape3D.new()
	cs.radius = 0.3 * s
	cs.height = 3.0 * s
	_shape(body, cs)


func _bocage() -> void:
	# Haies latérales et transversales (trouées : route + passages de flanc)
	hedge(Vector3(-38, 0, 46), Vector3(-38, 0, 108), [[32, 36]])
	hedge(Vector3(38, 0, 46), Vector3(38, 0, 108), [[32, 36]])
	hedge(Vector3(-38, 0, 78), Vector3(38, 0, 78), [[14, 18], [34, 42], [56, 60]])
	hedge(Vector3(-38, 0, 58), Vector3(38, 0, 58), [[26, 30], [34, 42], [64, 68]])
	hedge(Vector3(-38, 0, 108), Vector3(38, 0, 108), [])
	hedge(Vector3(-70, 0, 46), Vector3(-38, 0, 46), [[14, 18]])
	hedge(Vector3(38, 0, 46), Vector3(70, 0, 46), [[14, 18]])
	# Planeur écrasé dans le champ de départ
	var g := Node3D.new()
	g.position = Vector3(-17, 0, 92)
	g.rotation.y = deg_to_rad(25)
	nav.add_child(g)
	box(Vector3(0, 1.1, 0), Vector3(2.2, 2.2, 12), C_OLIVE, 0.0, true, g)
	box(Vector3(0, 1.2, -6.6), Vector3(2.0, 1.9, 1.4), C_OLIVE.darkened(0.2), 0.0, true, g)
	box(Vector3(0, 0.25, 1.5), Vector3(15, 0.22, 2.4), C_OLIVE.lightened(0.05), 0.0, false, g)
	box(Vector3(0.3, 2.5, 6.2), Vector3(0.2, 2.6, 1.6), C_OLIVE, 0.0, false, g)
	box(Vector3(9.5, 0.6, -2), Vector3(5, 0.2, 2.2), C_OLIVE.lightened(0.05), 30.0, false)
	cover(Vector3(-14, 0, 90))
	cover(Vector3(-20, 0, 95))
	# Arbres, meules, cratères
	for p: Vector3 in [Vector3(20, 0, 98), Vector3(28, 0, 88), Vector3(-30, 0, 70), Vector3(25, 0, 66),
			Vector3(-26, 0, 100), Vector3(12, 0, 86)]:
		tree(p, rng.randf_range(1.0, 1.4))
	# Parachute accroché dans un arbre
	var chute := SphereMesh.new()
	chute.radius = 2.0
	chute.height = 1.4
	chute.is_hemisphere = true
	chute.radial_segments = 10
	chute.rings = 3
	mesh(chute, Vector3(20.6, 6.6, 98.4), Color(0.85, 0.84, 0.78), Vector3(20, 0, 15))
	for p: Vector3 in [Vector3(-12, 0, 66), Vector3(18, 0, 92), Vector3(-25, 0, 84), Vector3(8, 0, 64)]:
		cyl(p + Vector3.UP * 0.8, 1.3, 1.6, _vary(C_HAY, 0.04), 8, true)
		cover(p + Vector3(0, 0, -2.0))
		cover(p + Vector3(0, 0, 2.0))
	for p: Vector3 in [Vector3(6, 0, 88), Vector3(-8, 0, 70), Vector3(22, 0, 52), Vector3(-20, 0, 60)]:
		cyl(p + Vector3.UP * 0.02, rng.randf_range(1.6, 2.6), 0.04, Color(0.25, 0.22, 0.16), 9, false)
	# Épave de jeep au départ
	_wreck(Vector3(-6, 0, 101), 70.0, Color(0.28, 0.3, 0.2))


func _wreck(pos: Vector3, rot: float, c: Color) -> void:
	var w := Node3D.new()
	w.position = pos
	w.rotation.y = deg_to_rad(rot)
	nav.add_child(w)
	box(Vector3(0, 0.6, 0), Vector3(1.6, 0.8, 3.3), c, 0.0, true, w)
	box(Vector3(0, 1.1, -0.9), Vector3(1.5, 0.1, 0.05), C_DARK, 0.0, false, w)
	for x: float in [-0.8, 0.8]:
		for z: float in [-1.1, 1.1]:
			var wheel := CylinderMesh.new()
			wheel.top_radius = 0.35
			wheel.bottom_radius = 0.35
			wheel.height = 0.22
			wheel.radial_segments = 8
			mesh(wheel, Vector3(x, 0.35, z), C_DARK, Vector3(0, 0, 90), w)


# --- Village ---------------------------------------------------------------------

## Maison : murs en moellons ou colombages enduits, couverture en tuiles/ardoises,
## fenêtres à encadrement et croisillons, appuis, volets, bacs à fleurs, porte, cheminée.
## `damage` > 0 : toit éventré et façades noircies.
func house(center: Vector3, w: float, d: float, h: float, style := "stone", roof_c := C_ROOF, damage := 0.0) -> void:
	var hold := Node3D.new()
	hold.position = center
	nav.add_child(hold)
	var colombage := style == "colombage"
	var wall_c := C_PLASTER if colombage else _vary(C_STONE, 0.05)
	var wall_mat: Material = Mats.plaster(wall_c, damage * 0.7) if colombage else Mats.stone(wall_c, damage * 0.7)
	box(Vector3(0, h * 0.5, 0), Vector3(w, h, d), wall_mat, 0.0, true, hold)
	# Soubassement en pierre plus sombre
	box(Vector3(0, 0.3, 0), Vector3(w + 0.08, 0.6, d + 0.08), Mats.stone(C_STONE2.darkened(0.1)), 0.0, false, hold)
	var roof := PrismMesh.new()
	roof.size = Vector3(w + 0.8, h * 0.6, d + 0.6)
	var slate := roof_c == C_SLATE
	mesh(roof, Vector3(0, h + h * 0.3, 0), Mats.roof(roof_c, wall_c, slate), Vector3.ZERO, hold)
	# Rives de toit (planches de bord)
	for sz: float in [-1.0, 1.0]:
		var half := (w + 0.8) * 0.5
		var ang := rad_to_deg(atan2(h * 0.6, half))
		for sx: float in [-1.0, 1.0]:
			box(Vector3(sx * half * 0.5, h + h * 0.3, sz * (d * 0.5 + 0.31)), Vector3(half * 1.12, 0.12, 0.08),
				C_WOOD.darkened(0.3), 0.0, false, hold).rotation_degrees = Vector3(0, 0, -sx * ang)
	box(Vector3(w * 0.22, h + h * 0.45, d * 0.3), Vector3(0.7, h * 0.5, 0.7), Mats.stone(C_STONE2), 0.0, false, hold)
	box(Vector3(w * 0.22, h + h * 0.72, d * 0.3), Vector3(0.85, 0.12, 0.85), C_STONE2.darkened(0.2), 0.0, false, hold)
	var shutter: Color = SHUTTERS[rng.randi() % SHUTTERS.size()]
	var floors := [1.6, 3.9] if h > 5.0 else [1.6]
	var door_side := -signf(center.x) if absf(center.x) > 1.0 else 1.0
	for sx: float in [-1.0, 1.0]:
		var x := sx * (w * 0.5)
		var n := maxi(1, int(d / 3.2))
		if colombage:
			var nb := int(d / 1.4)
			for i in nb + 1:
				box(Vector3(x + sx * 0.04, h * 0.5, -d * 0.5 + i * d / nb), Vector3(0.08, h, 0.16), C_BEAM, 0.0, false, hold)
			for y: float in [0.65, h * 0.5, h - 0.1]:
				box(Vector3(x + sx * 0.04, y, 0), Vector3(0.08, 0.16, d), C_BEAM, 0.0, false, hold)
			# Croix de Saint-André entre les poteaux d'angle
			for zz: float in [-d * 0.5 + d / nb * 0.5, d * 0.5 - d / nb * 0.5]:
				for diag: float in [-1.0, 1.0]:
					var brace := box(Vector3(x + sx * 0.045, h * 0.75, zz), Vector3(0.07, h * 0.62, 0.12), C_BEAM, 0.0, false, hold)
					brace.rotation_degrees.x = diag * 32.0
		for i in n:
			var z := -d * 0.5 + (i + 0.5) * d / n
			for fy: float in floors:
				if fy < 2.0 and sx == door_side and i == n / 2:
					_door(hold, Vector3(x, 0, z), sx)
					continue
				_window(hold, Vector3(x, fy, z), sx, shutter, fy > 2.0 and rng.randf() < 0.5)
	for sz: float in [-1.0, 1.0]:
		for fy: float in floors:
			_window_z(hold, Vector3(0, fy, sz * d * 0.5), sz)
	if damage > 0.0:
		_roof_hole(hold, w, d, h)
	# Végétation au pied des murs (côté cour)
	for i in 3:
		var side := -door_side
		var p := center + Vector3(side * (w * 0.5 + 0.7), 0, rng.randf_range(-d * 0.4, d * 0.4))
		nature.add_at("Bush_Small_Flowers" if rng.randf() < 0.5 else "Bush_Small", p, rng.randf_range(1.0, 1.5), rng.randf() * TAU)
	# Couvertures aux angles
	for cx: float in [-1.0, 1.0]:
		for cz: float in [-1.0, 1.0]:
			cover(center + Vector3(cx * (w * 0.5 + 0.9), 0, cz * (d * 0.5 - 0.5)))


## Fenêtre sur une façade ±X : encadrement, vitre sombre, croisillons, appui, volets ouverts.
func _window(hold: Node3D, p: Vector3, sx: float, shutter: Color, flower_box: bool) -> void:
	var x := p.x
	box(Vector3(x + sx * 0.03, p.y, p.z), Vector3(0.06, 1.12, 0.92), C_FRAME, 0.0, false, hold)
	box(Vector3(x + sx * 0.05, p.y, p.z), Vector3(0.04, 0.96, 0.76), C_GLASS, 0.0, false, hold)
	box(Vector3(x + sx * 0.075, p.y, p.z), Vector3(0.03, 0.96, 0.05), C_FRAME, 0.0, false, hold)
	box(Vector3(x + sx * 0.075, p.y + 0.1, p.z), Vector3(0.03, 0.05, 0.76), C_FRAME, 0.0, false, hold)
	box(Vector3(x + sx * 0.09, p.y - 0.6, p.z), Vector3(0.18, 0.08, 1.04), C_STONE2.lightened(0.1), 0.0, false, hold)
	box(Vector3(x + sx * 0.07, p.y + 0.62, p.z), Vector3(0.12, 0.12, 1.1), C_STONE2, 0.0, false, hold)
	for sz: float in [-1.0, 1.0]:
		var sh := box(Vector3(x + sx * 0.08, p.y, p.z + sz * 0.68), Vector3(0.05, 1.04, 0.42), shutter, 0.0, false, hold)
		sh.rotation_degrees.y = sz * sx * -12.0
	if flower_box:
		box(Vector3(x + sx * 0.2, p.y - 0.7, p.z), Vector3(0.24, 0.2, 0.86), C_WOOD, 0.0, false, hold)
		nature.add_at("Flower_%d_Clump" % (1 + rng.randi() % 4), hold.global_position + Vector3(x + sx * 0.2, p.y - 0.6, p.z),
			1.4, rng.randf() * TAU)


## Petite fenêtre de pignon (façade ±Z).
func _window_z(hold: Node3D, p: Vector3, sz: float) -> void:
	box(Vector3(p.x, p.y, p.z + sz * 0.03), Vector3(0.84, 1.04, 0.06), C_FRAME, 0.0, false, hold)
	box(Vector3(p.x, p.y, p.z + sz * 0.05), Vector3(0.68, 0.88, 0.04), C_GLASS, 0.0, false, hold)
	box(Vector3(p.x, p.y, p.z + sz * 0.075), Vector3(0.05, 0.88, 0.03), C_FRAME, 0.0, false, hold)
	box(Vector3(p.x, p.y - 0.55, p.z + sz * 0.09), Vector3(0.96, 0.08, 0.18), C_STONE2.lightened(0.1), 0.0, false, hold)


func _door(hold: Node3D, p: Vector3, sx: float) -> void:
	box(Vector3(p.x + sx * 0.03, 1.15, p.z), Vector3(0.06, 2.4, 1.36), C_STONE2.lightened(0.05), 0.0, false, hold)
	box(Vector3(p.x + sx * 0.05, 1.08, p.z), Vector3(0.05, 2.16, 1.06), C_WOOD.darkened(0.25), 0.0, false, hold)
	for k in 4:
		box(Vector3(p.x + sx * 0.08, 1.08, p.z - 0.4 + k * 0.27), Vector3(0.02, 2.1, 0.03), C_WOOD.darkened(0.45), 0.0, false, hold)
	box(Vector3(p.x + sx * 0.25, 0.06, p.z), Vector3(0.5, 0.12, 1.5), C_STONE2, 0.0, false, hold)


## Toit éventré par un obus : trou sombre et chevrons calcinés sur un versant.
func _roof_hole(hold: Node3D, w: float, d: float, h: float) -> void:
	var half := (w + 0.8) * 0.5
	var rh := h * 0.6
	var ang := atan2(rh, half)
	var n := Vector3(rh, half, 0).normalized()      # normale du versant +X
	var c := Vector3(half * 0.5, h + rh * 0.5, rng.randf_range(-d * 0.2, d * 0.2)) + n * 0.03
	var hole := box(c, Vector3(half * 0.7, 0.04, 2.6), Color(0.05, 0.04, 0.04), 0.0, false, hold)
	hole.rotation = Vector3(0, 0, -ang)
	for k in 4:
		var raf := box(c + n * 0.06 + Vector3(0, 0, -1.0 + k * 0.66), Vector3(half * 0.9, 0.12, 0.12),
			C_BURNT, 0.0, false, hold)
		raf.rotation = Vector3(0, 0, -ang + rng.randf_range(-0.1, 0.1))


## Maison en ruine, ouverte côté est : murs déchiquetés, gravats, fumée.
func ruin(center: Vector3, w: float, d: float, h: float) -> void:
	var t := 0.5
	# Mur ouest plein (déchiqueté)
	_jagged_wall(center + Vector3(-w * 0.5, 0, 0), d, h, 90.0, [])
	# Murs nord et sud avec ouverture
	_jagged_wall(center + Vector3(0, 0, -d * 0.5), w, h, 0.0, [[w * 0.55, w * 0.75]])
	_jagged_wall(center + Vector3(0, 0, d * 0.5), w, h * 0.8, 0.0, [[w * 0.3, w * 0.48]])
	# Côté est : muret effondré (couverture)
	box(center + Vector3(w * 0.5, 0.5, -d * 0.3), Vector3(t, 1.0, d * 0.35), Mats.stone(C_STONE2, 0.3))
	box(center + Vector3(w * 0.5, 0.45, d * 0.32), Vector3(t, 0.9, d * 0.3), Mats.stone(C_STONE2, 0.3))
	cover(center + Vector3(w * 0.5 - 0.9, 0, -d * 0.3))
	cover(center + Vector3(w * 0.5 - 0.9, 0, d * 0.32))
	# Gravats et poutres calcinées
	for i in 7:
		var p := center + Vector3(rng.randf_range(-w * 0.35, w * 0.35), 0.2, rng.randf_range(-d * 0.35, d * 0.35))
		box(p, Vector3(rng.randf_range(0.4, 1.0), 0.4, rng.randf_range(0.4, 1.0)), Mats.stone(C_STONE2, 0.4),
			rng.randf_range(0, 90), false)
		nature.add_at("Rock_%d" % (1 + rng.randi() % 5), p + Vector3(rng.randf_range(-0.8, 0.8), -0.2, 0.5),
			rng.randf_range(0.5, 0.9), rng.randf() * TAU)
	for i in 3:
		var p := center + Vector3(rng.randf_range(-w * 0.3, w * 0.3), 0.3, rng.randf_range(-d * 0.3, d * 0.3))
		mesh(boxm(Vector3(0.2, 0.2, 4.0)), p, C_BURNT, Vector3(rng.randf_range(-15, 15), rng.randf_range(0, 180), 0))
	Fx.smoke_column(root, center + Vector3(-1, 0.5, 0), Color(0.22, 0.22, 0.22), 1.0, true)


func _jagged_wall(center: Vector3, length: float, h: float, rot: float, gaps: Array) -> void:
	var dir := Vector3(cos(deg_to_rad(rot)), 0, -sin(deg_to_rad(rot)))
	var start := center - dir * length * 0.5
	var s := 0.0
	while s < length - 0.1:
		var seg := minf(rng.randf_range(1.2, 2.4), length - s)
		var mid_s := s + seg * 0.5
		var in_gap := false
		for g: Array in gaps:
			if mid_s > float(g[0]) and mid_s < float(g[1]):
				in_gap = true
		if not in_gap:
			var sh := h * rng.randf_range(0.45, 1.0)
			box(start + dir * mid_s + Vector3.UP * sh * 0.5, Vector3(seg, sh, 0.5), Mats.stone(C_STONE, 0.55), rot)
		s += seg


func church(center: Vector3) -> void:
	# Nef
	var stone2 := Mats.stone(C_STONE2)
	box(center + Vector3(0, 4.5, 0), Vector3(12, 9, 22), stone2)
	var roof := PrismMesh.new()
	roof.size = Vector3(13, 5, 23)
	mesh(roof, center + Vector3(0, 11.5, 0), Mats.roof(C_SLATE, C_STONE2, true))
	for sx: float in [-1.0, 1.0]:
		for i in 4:
			var wz := -7.5 + i * 5.0
			# Vitrail en lancette + encadrement, contreforts entre les baies
			box(center + Vector3(sx * 6.02, 4.8, wz), Vector3(0.1, 3.6, 1.3), C_STONE.lightened(0.1), 0.0, false)
			box(center + Vector3(sx * 6.06, 4.8, wz), Vector3(0.06, 3.3, 0.95), Color(0.22, 0.26, 0.38), 0.0, false)
			box(center + Vector3(sx * 6.09, 4.8, wz), Vector3(0.03, 3.3, 0.06), C_DARK, 0.0, false)
			cyl(center + Vector3(sx * 6.06, 6.45, wz), 0.47, 0.06, Color(0.22, 0.26, 0.38), 8, false).rotation_degrees.z = 90.0
			box(center + Vector3(sx * 6.4, 2.5, wz + 2.5), Vector3(0.8, 5.0, 0.9), stone2, 0.0, true)
			box(center + Vector3(sx * 6.25, 5.3, wz + 2.5), Vector3(0.5, 1.0, 0.9), stone2, 0.0, false).rotation_degrees.z = sx * 25.0
	# Clocher (au sud, face à la place)
	var tz := center.z + 14.0
	box(Vector3(center.x, 9, tz), Vector3(6.5, 18, 6.5), Mats.stone(C_STONE))
	for y: float in [6.0, 12.0, 17.8]:
		box(Vector3(center.x, y, tz), Vector3(6.8, 0.3, 6.8), C_STONE2, 0.0, false)
	for sx2: float in [-1.0, 1.0]:
		for sz2: float in [-1.0, 1.0]:
			box(Vector3(center.x + sx2 * 3.15, 5.0, tz + sz2 * 3.15), Vector3(0.9, 10.0, 0.9), Mats.stone(C_STONE2), 0.0, false)
	var spire := CylinderMesh.new()
	spire.top_radius = 0.0
	spire.bottom_radius = 4.7
	spire.height = 8.0
	spire.radial_segments = 4
	spire.rings = 1
	mesh(spire, Vector3(center.x, 22, tz), Mats.roof(C_SLATE, C_SLATE, true), Vector3(0, 45, 0))
	cyl(Vector3(center.x, 26.6, tz), 0.04, 1.4, C_DARK, 4, false)
	box(Vector3(center.x, 26.9, tz), Vector3(0.6, 0.05, 0.05), C_DARK, 0.0, false)
	box(Vector3(center.x, 1.8, tz + 3.27), Vector3(2.6, 3.8, 0.12), C_STONE.lightened(0.1), 0.0, false)
	box(Vector3(center.x, 1.6, tz + 3.31), Vector3(2.0, 3.2, 0.1), C_WOOD.darkened(0.3), 0.0, false)
	box(Vector3(center.x, 14.5, tz + 3.27), Vector3(1.2, 2.2, 0.1), C_DARK, 0.0, false)
	cyl(Vector3(center.x, 11.0, tz + 3.3), 0.9, 0.06, Color(0.9, 0.88, 0.8), 12, false).rotation_degrees.x = 90.0
	box(Vector3(center.x, 0.02, tz + 4.5), Vector3(8, 0.04, 2.5), C_COBBLE.lightened(0.1), 0.0, false)
	cover(Vector3(center.x - 4.2, 0, tz + 3.5))
	cover(Vector3(center.x + 4.2, 0, tz + 3.5))


func cart(pos: Vector3, rot: float) -> void:
	var body := _static(pos, rot)
	var s := BoxShape3D.new()
	s.size = Vector3(1.6, 1.3, 3.0)
	_shape(body, s, Vector3(0, 0.65, 0))
	mesh(boxm(Vector3(1.5, 0.45, 2.8)), Vector3(0, 0.85, 0), C_WOOD, Vector3.ZERO, body)
	mesh(boxm(Vector3(1.3, 0.55, 2.2)), Vector3(0, 1.35, 0.2), C_HAY, Vector3.ZERO, body)
	var wheel := CylinderMesh.new()
	wheel.top_radius = 0.6
	wheel.bottom_radius = 0.6
	wheel.height = 0.12
	wheel.radial_segments = 10
	for sx: float in [-0.82, 0.82]:
		mesh(wheel, Vector3(sx, 0.6, 0.3), C_WOOD.darkened(0.25), Vector3(0, 0, 90), body)
	mesh(boxm(Vector3(0.1, 0.1, 2.0)), Vector3(0.4, 0.5, -2.2), C_WOOD, Vector3(-12, 0, 0), body)
	mesh(boxm(Vector3(0.1, 0.1, 2.0)), Vector3(-0.4, 0.5, -2.2), C_WOOD, Vector3(-12, 0, 0), body)
	var right := Vector3(cos(deg_to_rad(rot)), 0, -sin(deg_to_rad(rot)))
	cover(pos + right * 1.4)
	cover(pos - right * 1.4)


func truck(pos: Vector3, rot: float, c: Color, burnt := false) -> void:
	var body := _static(pos, rot)
	var s := BoxShape3D.new()
	s.size = Vector3(2.3, 2.5, 6.2)
	_shape(body, s, Vector3(0, 1.25, 0))
	var col := C_BURNT if burnt else c
	mesh(boxm(Vector3(2.2, 0.9, 6.0)), Vector3(0, 0.95, 0), col, Vector3.ZERO, body)
	mesh(boxm(Vector3(2.1, 1.4, 1.7)), Vector3(0, 1.95, -2.0), col.lightened(0.05), Vector3.ZERO, body)
	mesh(boxm(Vector3(1.9, 0.6, 0.1)), Vector3(0, 2.2, -2.86), C_DARK, Vector3.ZERO, body)
	if not burnt:
		mesh(boxm(Vector3(2.2, 1.6, 3.8)), Vector3(0, 2.2, 1.0), c.darkened(0.1), Vector3.ZERO, body)
	var wheel := CylinderMesh.new()
	wheel.top_radius = 0.5
	wheel.bottom_radius = 0.5
	wheel.height = 0.3
	wheel.radial_segments = 10
	for sx: float in [-1.05, 1.05]:
		for sz: float in [-2.0, 1.8]:
			mesh(wheel, Vector3(sx, 0.5, sz), C_DARK, Vector3(0, 0, 90), body)
	var right := Vector3(cos(deg_to_rad(rot)), 0, -sin(deg_to_rad(rot)))
	var fwd := Vector3(-sin(deg_to_rad(rot)), 0, -cos(deg_to_rad(rot)))
	cover(pos + right * 1.9 + fwd * 1.5)
	cover(pos - right * 1.9 - fwd * 1.5)
	if burnt:
		Fx.smoke_column(root, pos + Vector3.UP * 1.5, Color(0.15, 0.15, 0.15), 0.7, false)


func crates(pos: Vector3, rot: float) -> void:
	box(pos + Vector3(0, 0.5, 0), Vector3(1.0, 1.0, 1.0), C_WOOD, rot)
	box(pos + Vector3(1.05, 0.5, 0.1), Vector3(1.0, 1.0, 1.0), C_WOOD.lightened(0.05), rot + 8.0)
	box(pos + Vector3(0.4, 1.4, 0.05), Vector3(0.9, 0.8, 0.9), C_WOOD.darkened(0.08), rot - 6.0)
	cover(pos + Vector3(0.5, 0, 1.3))
	cover(pos + Vector3(0.5, 0, -1.3))


## Arc de sacs de sable (angles en degrés, 0 = +X, 90 = +Z/sud).
func sandbags(center: Vector3, radius: float, a0: float, a1: float, layers := 3) -> void:
	var body := _static(Vector3.ZERO)
	var arc := deg_to_rad(a1 - a0) * radius
	var n := maxi(1, int(arc / 0.62))
	for i in n:
		var a := deg_to_rad(lerpf(a0, a1, (i + 0.5) / n))
		var p := center + Vector3(cos(a), 0, sin(a)) * radius
		var yaw := -(a + PI * 0.5)
		for l in layers:
			var bag := boxm(Vector3(0.6, 0.27, 0.38))
			var mi := mesh(bag, p + Vector3.UP * (0.14 + l * 0.26), _vary(C_SAND, 0.04),
				Vector3(0, rad_to_deg(yaw) + rng.randf_range(-6, 6), 0), body)
			mi.position += Vector3(cos(a + PI * 0.5), 0, sin(a + PI * 0.5)) * (0.15 if l % 2 == 1 else 0.0)
		var s := BoxShape3D.new()
		s.size = Vector3(0.66, layers * 0.27, 0.42)
		_shape(body, s, p + Vector3.UP * layers * 0.135, Vector3(0, yaw, 0))
		if i % 3 == 1:
			cover(center + Vector3(cos(a), 0, sin(a)) * (radius - 0.9))


func sandbag_line(a: Vector3, b: Vector3, layers := 3) -> void:
	var dir := (b - a).normalized()
	var ang := atan2(dir.z, dir.x)
	var body := _static(Vector3.ZERO)
	var length := a.distance_to(b)
	var n := maxi(1, int(length / 0.62))
	for i in n:
		var p := a + dir * (i + 0.5) * length / n
		for l in layers:
			mesh(boxm(Vector3(0.6, 0.27, 0.38)), p + Vector3.UP * (0.14 + l * 0.26), _vary(C_SAND, 0.04),
				Vector3(0, -rad_to_deg(ang) + rng.randf_range(-6, 6), 0), body)
	var s := BoxShape3D.new()
	s.size = Vector3(length, layers * 0.27, 0.42)
	_shape(body, s, (a + b) * 0.5 + Vector3.UP * layers * 0.135, Vector3(0, -ang, 0))
	var side := Vector3(-dir.z, 0, dir.x)
	for k in maxi(1, int(length / 3.0)):
		var p := a + dir * (k + 0.5) * length / maxi(1, int(length / 3.0))
		cover(p + side * 0.9)
		cover(p - side * 0.9)


func low_wall(a: Vector3, b: Vector3, h := 1.1) -> void:
	var dir := b - a
	var length := dir.length()
	var yaw := rad_to_deg(atan2(dir.x, dir.z))
	box((a + b) * 0.5 + Vector3.UP * h * 0.5, Vector3(0.5, h, length), Mats.stone(C_STONE2), yaw)
	box((a + b) * 0.5 + Vector3.UP * (h + 0.06), Vector3(0.62, 0.12, length + 0.1), C_STONE2.darkened(0.15), yaw, false)
	for k in int(length / 2.5):
		nature.add_at("Plant_%d" % (1 + rng.randi() % 2), a + dir * (k + 0.5) / int(length / 2.5)
			+ Vector3(dir.z, 0, -dir.x).normalized() * 0.6 * (1.0 if k % 2 == 0 else -1.0), rng.randf_range(0.7, 1.0), rng.randf() * TAU)
	var side := Vector3(dir.z, 0, -dir.x) / length
	for k in maxi(1, int(length / 4.0)):
		var p := a + dir * (k + 0.5) / maxi(1, int(length / 4.0))
		cover(p + side * 0.9)
		cover(p - side * 0.9)


func _village() -> void:
	# Entrée : murets de part et d'autre de la route
	low_wall(Vector3(-20, 0, 42), Vector3(-5, 0, 42))
	low_wall(Vector3(5, 0, 42), Vector3(20, 0, 42))
	# Maisons de la rue
	house(Vector3(-10, 0, 34), 8, 11, 6, "colombage")
	house(Vector3(-10, 0, 20), 8, 10, 5.5)
	house(Vector3(10, 0, 36), 8, 10, 6)
	house(Vector3(10.5, 0, 22), 9, 11, 6.5, "colombage", C_ROOF, 1.0)
	Fx.smoke_column(root, Vector3(10.5, 8.5, 22), Color(0.2, 0.2, 0.2), 1.3, true)
	cart(Vector3(5.5, 0, 26), 10.0)
	crates(Vector3(-5.5, 0, 30), 5.0)
	# Place : maisons autour
	house(Vector3(-25, 0, 6.5), 10, 11, 6)
	ruin(Vector3(-25, 0, -10.5), 10, 9, 5.5)
	house(Vector3(25, 0, 6.5), 10, 11, 6.5, "colombage")
	house(Vector3(25, 0, -10.5), 10, 9, 6)
	house(Vector3(-15, 0, -24), 8, 10, 6, "colombage", C_SLATE)
	house(Vector3(15, 0, -24), 8, 10, 5.5, "stone", C_ROOF, 0.6)
	church(Vector3(0, 0, -36))
	# Mobilier de la place
	cyl(Vector3(-6, 0.45, -3), 1.0, 0.9, Mats.stone(C_STONE2), 12)
	cyl(Vector3(-6, 0.93, -3), 1.08, 0.08, C_STONE2.darkened(0.15), 12, false)
	cyl(Vector3(-6, 1.6, -3.9), 0.06, 2.2, C_WOOD, 5, false)
	cyl(Vector3(-6, 1.6, -2.1), 0.06, 2.2, C_WOOD, 5, false)
	box(Vector3(-6, 2.8, -3), Vector3(1.4, 0.15, 2.2), C_ROOF, 0.0, false)
	cover(Vector3(-7.6, 0, -3))
	cover(Vector3(-4.4, 0, -3))
	cart(Vector3(-12, 0, 4), 30.0)
	truck(Vector3(12, 0, 2), 75.0, C_BURNT, true)
	crates(Vector3(8, 0, 7), 10.0)
	crates(Vector3(-15, 0, -8), -15.0)
	# Nid de mitrailleuse devant l'église
	sandbags(Vector3(2, 0, -12.6), 2.0, 15.0, 165.0, 3)
	sandbag_line(Vector3(-12, 0, -13), Vector3(-6, 0, -13), 3)
	sandbag_line(Vector3(10, 0, -13), Vector3(16, 0, -14), 3)
	# Arbres de la place
	for p: Vector3 in [Vector3(-17, 0, 9), Vector3(17, 0, -2), Vector3(-30, 0, 24), Vector3(30, 0, 30)]:
		tree(p, 1.1)


# --- Site du canon de 88 -----------------------------------------------------------------

func _flak_site() -> void:
	var c := Vector3(50, 0, -2)
	sandbags(c, 6.5, -150.0, 150.0, 4)   # ouverture à l'ouest
	flak = _static(c, 0.0)
	flak.name = "Flak88"
	var s := BoxShape3D.new()
	s.size = Vector3(3.2, 2.2, 3.2)
	_shape(flak, s, Vector3(0, 1.1, 0))
	# Affût cruciforme
	mesh(boxm(Vector3(6.5, 0.3, 0.7)), Vector3(0, 0.35, 0), C_FLAK, Vector3.ZERO, flak)
	mesh(boxm(Vector3(0.7, 0.3, 6.5)), Vector3(0, 0.35, 0), C_FLAK, Vector3.ZERO, flak)
	var ped := CylinderMesh.new()
	ped.top_radius = 0.5
	ped.bottom_radius = 0.7
	ped.height = 1.1
	ped.radial_segments = 8
	mesh(ped, Vector3(0, 1.0, 0), C_FLAK, Vector3.ZERO, flak)
	mesh(boxm(Vector3(1.4, 0.9, 2.2)), Vector3(0, 1.9, 0), C_FLAK.darkened(0.08), Vector3.ZERO, flak)
	mesh(boxm(Vector3(2.4, 1.6, 0.08)), Vector3(0, 2.2, -1.5), C_FLAK, Vector3(-10, 0, 0), flak)
	flak_barrel = Node3D.new()
	flak_barrel.position = Vector3(0, 2.1, 0)
	flak_barrel.rotation_degrees = Vector3(32, 30, 0)
	flak.add_child(flak_barrel)
	var bar := CylinderMesh.new()
	bar.top_radius = 0.09
	bar.bottom_radius = 0.14
	bar.height = 6.0
	bar.radial_segments = 8
	mesh(bar, Vector3(0, 0, -2.6), C_FLAK.darkened(0.15), Vector3(90, 0, 0), flak_barrel)
	mesh(boxm(Vector3(0.5, 0.5, 2.0)), Vector3(0, 0, 0.2), C_FLAK.darkened(0.1), Vector3.ZERO, flak_barrel)
	# Obus, caisses, filet de camouflage
	crates(c + Vector3(3.5, 0, 3.5), 20.0)
	crates(c + Vector3(-3.0, 0, -4.0), -10.0)
	for i in 4:
		cyl(c + Vector3(4.2, 0.35, -2.5 + i * 0.35), 0.1, 0.7, Color(0.6, 0.5, 0.25), 6, false)
	var net := mesh(boxm(Vector3(11, 0.05, 11)), c + Vector3(0, 4.2, 0), Color(0.3, 0.33, 0.2))
	net.rotation_degrees = Vector3(3, 0, -4)
	for p: Vector2 in [Vector2(-5, -5), Vector2(5, -5), Vector2(-5, 5), Vector2(5, 5)]:
		cyl(c + Vector3(p.x, 2.1, p.y), 0.08, 4.2, C_WOOD, 5, false)
	tree(Vector3(60, 0, 8), 1.3)
	tree(Vector3(42, 0, -14), 1.2)
	tree(Vector3(58, 0, -15), 1.1)
	truck(Vector3(40, 0, 8), -20.0, Color(0.4, 0.42, 0.36))


## Remplace le canon intact par une épave fumante.
func destroy_flak() -> void:
	if flak == null:
		return
	for child in flak.get_children():
		if child is MeshInstance3D:
			(child as MeshInstance3D).material_override = mat(C_BURNT)
	for child in flak_barrel.get_children():
		if child is MeshInstance3D:
			(child as MeshInstance3D).material_override = mat(C_BURNT)
	var tw := flak.create_tween()
	tw.tween_property(flak_barrel, "rotation_degrees", Vector3(-8, 55, 14), 0.6).set_trans(Tween.TRANS_BOUNCE)
	Fx.smoke_column(root, flak.global_position + Vector3.UP * 1.5, Color(0.12, 0.12, 0.12), 1.4, true)


# --- Point de ralliement (ouest) -------------------------------------------------------

func _rally_site() -> void:
	var c := Vector3(-58, 0, -2)
	truck(c + Vector3(3, 0, -7), 90.0, C_OLIVE)
	sandbags(c, 5.0, 20.0, 160.0, 3)
	Fx.smoke_column(root, c + Vector3(0, 0.2, -2), Color(0.35, 0.7, 0.3), 0.8, false)
	for p: Vector3 in [Vector3(-48, 0, 18), Vector3(-44, 0, 28), Vector3(-55, 0, 25), Vector3(-60, 0, 14),
			Vector3(-40, 0, 12), Vector3(-50, 0, -20), Vector3(-62, 0, -28)]:
		tree(p, rng.randf_range(0.9, 1.2))


# --- Champs au nord (arrivée de la contre-attaque) --------------------------------------

func _north_fields() -> void:
	hedge(Vector3(-66, 0, -60), Vector3(66, 0, -60), [[52, 60], [76, 84], [106, 114]])
	hedge(Vector3(30, 0, 12), Vector3(30, 0, 44), [[12, 16]])
	hedge(Vector3(-30, 0, -20), Vector3(-30, 0, -55), [[10, 14]])
	for p: Vector3 in [Vector3(-20, 0, -48), Vector3(22, 0, -46), Vector3(35, 0, -35), Vector3(-40, 0, -40),
			Vector3(10, 0, -70), Vector3(-25, 0, -75), Vector3(48, 0, -72), Vector3(55, 0, -45)]:
		tree(p, rng.randf_range(1.0, 1.4))
	for p: Vector3 in [Vector3(-8, 0, -68), Vector3(30, 0, -64), Vector3(-45, 0, -70)]:
		cyl(p + Vector3.UP * 0.8, 1.3, 1.6, _vary(C_HAY, 0.04), 8, true)
		cover(p + Vector3(0, 0, 2.0))
	sandbag_line(Vector3(-4, 0, -52), Vector3(4, 0, -52), 3)


# --- Limites de la carte -----------------------------------------------------------------

func _bounds() -> void:
	var walls := [
		[Vector3(0, 5, -92), Vector3(150, 10, 1)], [Vector3(0, 5, 112), Vector3(150, 10, 1)],
		[Vector3(-72, 5, 10), Vector3(1, 10, 210)], [Vector3(72, 5, 10), Vector3(1, 10, 210)],
	]
	for wdef: Array in walls:
		var body := _static(wdef[0])
		var s := BoxShape3D.new()
		s.size = wdef[1]
		_shape(body, s)
	# Rideaux d'arbres pour fermer visuellement
	for x in range(-70, 71, 7):
		tree(Vector3(x + rng.randf_range(-2, 2), 0, -89), rng.randf_range(1.1, 1.6))
		tree(Vector3(x + rng.randf_range(-2, 2), 0, 110), rng.randf_range(1.1, 1.6))
	for z in range(-85, 108, 7):
		tree(Vector3(-69, 0, z + rng.randf_range(-2, 2)), rng.randf_range(1.1, 1.6))
		tree(Vector3(69, 0, z + rng.randf_range(-2, 2)), rng.randf_range(1.1, 1.6))
	# Fumées lointaines (ambiance)
	for p: Vector3 in [Vector3(-110, 0, -70), Vector3(120, 0, 20), Vector3(60, 0, -140), Vector3(-90, 0, 90)]:
		Fx.smoke_column(root, p, Color(0.25, 0.25, 0.25), 3.0, false)


# --- Couvert végétal ------------------------------------------------------------------

## Herbe, fleurs, plantes et rochers sur toutes les zones libres (hors routes et murs).
## Densité selon la qualité graphique. Au pied des bâtiments : buissons et fleurs.
func _ground_cover() -> void:
	var density := 1.0 if Game.quality > 0 else 0.4
	var step := 1.25
	var z := -88.0
	while z < 108.0:
		var x := -68.0
		while x < 68.0:
			var p := Vector3(x + rng.randf_range(0.0, step), 0.0, z + rng.randf_range(0.0, step))
			x += step
			if rng.randf() > density or is_blocked(p) or is_paved(p):
				continue
			var village := absf(p.x) < 32.0 and p.z > -45.0 and p.z < 44.0
			if village and rng.randf() < 0.65:
				continue
			var near_wall := is_blocked(p + Vector3(1.2, 0, 0)) or is_blocked(p - Vector3(1.2, 0, 0)) \
				or is_blocked(p + Vector3(0, 0, 1.2)) or is_blocked(p - Vector3(0, 0, 1.2))
			var r := rng.randf()
			var yaw := rng.randf() * TAU
			if near_wall and r < 0.25:
				nature.add_at("Plant_%d" % (1 + rng.randi() % 2), p, rng.randf_range(0.8, 1.2), yaw)
			elif r < 0.07:
				nature.add_at("Flower_%d_Clump" % (1 + rng.randi() % 4), p, rng.randf_range(1.2, 1.8), yaw)
			elif r < 0.085:
				nature.add_at("Rock_%d" % (1 + rng.randi() % 5), p - Vector3(0, 0.15, 0), rng.randf_range(0.5, 1.2), yaw)
			elif r < 0.095 and not village:
				nature.add_at("Bush_Small", p, rng.randf_range(1.0, 1.6), yaw)
			else:
				nature.add_at("Grass_Large" if rng.randf() < 0.7 else "Grass_Small", p, rng.randf_range(1.1, 1.9), yaw)
		z += step
