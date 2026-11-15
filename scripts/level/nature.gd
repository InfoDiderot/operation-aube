class_name Nature
extends RefCounted
## Végétation Quaternius « Ultimate Stylized Nature » (CC0) : arbres, buissons, herbe, fleurs, rochers.
## Les meshes sont extraits des FBX, leurs matériaux remplacés (écorce, feuillage au vent),
## puis dessinés en MultiMesh : des milliers d'instances pour peu d'appels de rendu.

const FBX := "res://assets/nature/FBX/%s.fbx"
const TEX := "res://assets/nature/Textures/%s.png"

static var _meshes: Dictionary = {}
static var _base_scale: Dictionary = {}

var _batches: Dictionary = {}   # clé "nom|bloc" -> Array[Transform3D]
var _chunk := 16.0


## Mesh prêt à l'emploi (orientation corrigée, matériaux du jeu).
static func mesh(name: String) -> Mesh:
	if _meshes.has(name):
		return _meshes[name]
	var scene := (load(FBX % name) as PackedScene).instantiate()
	var mi := scene.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var m := mi.mesh.duplicate() as Mesh
	scene.free()
	for i in m.get_surface_count():
		var src := m.surface_get_material(i)
		m.surface_set_material(i, _material_for(src.resource_name if src else "", name))
	_meshes[name] = m
	# Certains FBX du pack sont exportés en centimètres
	var longest := m.get_aabb().get_longest_axis_size()
	_base_scale[name] = 100.0 if longest < 0.05 else 1.0
	return m


static func base_scale(name: String) -> float:
	mesh(name)
	return _base_scale[name]


static func _material_for(mat_name: String, mesh_name: String) -> Material:
	if mat_name.ends_with("_Bark") or mesh_name.begins_with("DeadTree"):
		var bark := mat_name if mat_name.ends_with("_Bark") else "NormalTree_Bark"
		var b := StandardMaterial3D.new()
		b.albedo_texture = load(TEX % bark)
		b.normal_enabled = true
		b.normal_texture = load(TEX % (bark + "_Normal"))
		b.roughness = 0.95
		if mesh_name.begins_with("DeadTree"):
			b.albedo_color = Color(0.55, 0.5, 0.45)
		return b
	if mat_name == "Rock" or mat_name == "Rocks":
		var r := StandardMaterial3D.new()
		r.albedo_texture = load(TEX % "Rocks")
		r.albedo_color = Color(0.85, 0.83, 0.78)
		r.roughness = 0.9
		return r
	var tex_name := mat_name
	var tint := Color.WHITE
	var sway := 0.1
	var height := 5.0
	match mat_name:
		"Grass":
			tint = Color(0.72, 0.85, 0.55)
			sway = 0.08
			height = 0.5
		"Flowers":
			sway = 0.05
			height = 0.6
		"Bush_Leaves":
			tint = Color(0.5, 0.66, 0.42)
			sway = 0.04
			height = 1.5
		"NormalTree_Leaves", "BirchTree_Leaves":
			tint = Color(0.62, 0.74, 0.5)
			sway = 0.12
			height = 7.0
	if not ResourceLoader.exists(TEX % tex_name):
		tex_name = "Leaves_BW"
	return Mats.foliage(load(TEX % tex_name), tint, sway, height)


## Ajoute une instance ; regroupée par bloc de 16 m pour le culling.
func add(name: String, xform: Transform3D) -> void:
	var c := Vector2i(floori(xform.origin.x / _chunk), floori(xform.origin.z / _chunk))
	var key := "%s|%d|%d" % [name, c.x, c.y]
	if not _batches.has(key):
		_batches[key] = []
	(_batches[key] as Array).append(xform)


func add_at(name: String, pos: Vector3, scale: float, yaw: float) -> void:
	var s := scale * base_scale(name)
	add(name, Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s), pos))


## Crée les MultiMeshInstance3D. Les petites plantes disparaissent au-delà de `small_range` m.
func flush(parent: Node3D, small_range := 60.0) -> int:
	var count := 0
	for key: String in _batches:
		var name := key.get_slice("|", 0)
		var xforms: Array = _batches[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh(name)
		mm.instance_count = xforms.size()
		for i in xforms.size():
			mm.set_instance_transform(i, xforms[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		var small := name.begins_with("Grass") or name.begins_with("Flower") or name.begins_with("Plant")
		if not small:
			mmi.visibility_range_end = 170.0
		if small:
			mmi.visibility_range_end = small_range
			mmi.visibility_range_end_margin = 8.0
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mmi)
		count += xforms.size()
	_batches.clear()
	return count
