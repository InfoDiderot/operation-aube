class_name SoldierModel
extends Node3D
## Soldat animé à partir du mannequin KayKit (CC0, Kay Lousberg) :
## teinte de faction, tête réduite (style « chibi » corrigé), casque et arme attachés aux os,
## AnimationTree : locomotion -> accroupi -> visée (haut du corps) -> tir -> actions -> mort.
## Le modèle regarde vers -Z, comme le reste du jeu.

const MANNEQUIN := "res://assets/characters/mannequin.glb"
const ANIM_FILES := [
	"res://assets/characters/Rig_Medium_General.glb",
	"res://assets/characters/Rig_Medium_MovementBasic.glb",
	"res://assets/characters/Rig_Medium_MovementAdvanced.glb",
	"res://assets/characters/Rig_Medium_CombatRanged.glb",
]
const LOOPING := ["Idle_A", "Walking_A", "Running_A", "Running_HoldingRifle", "Crouching", "Ranged_2H_Aiming"]
const UPPER_BONES := ["spine", "chest", "head", "upperarm.l", "lowerarm.l", "wrist.l", "hand.l",
	"upperarm.r", "lowerarm.r", "wrist.r", "hand.r"]
const SKEL := "Rig_Medium/Skeleton3D"
const HEAD_SCALE := 0.5
const LEG_SCALE := 1.45
const MODEL_SCALE := 0.93

const FACTIONS := {
	"axis": {"uniform": Color(0.36, 0.39, 0.33), "legs": Color(0.3, 0.32, 0.28),
		"helmet": Color(0.3, 0.32, 0.28), "skin": Color(0.82, 0.64, 0.52)},
	"allied": {"uniform": Color(0.42, 0.4, 0.27), "legs": Color(0.36, 0.33, 0.24),
		"helmet": Color(0.3, 0.33, 0.2), "skin": Color(0.78, 0.6, 0.48)},
}

var faction := "axis"
var weapon_kind := "rifle"
var gun_tip: Marker3D
var skeleton: Skeleton3D
var dead := false

var _tree: AnimationTree
var _root: Node3D
var _gun: Node3D
var _aim_t := 0.0
var _head_idx := -1
static var _library: AnimationLibrary
static var _mats: Dictionary = {}


## Bibliothèque d'animations fusionnée, construite une seule fois pour tous les soldats.
static func get_library() -> AnimationLibrary:
	if _library:
		return _library
	_library = AnimationLibrary.new()
	for path: String in ANIM_FILES:
		var scene := (load(path) as PackedScene).instantiate()
		for ap in scene.find_children("*", "AnimationPlayer", true, false):
			var player := ap as AnimationPlayer
			for anim_name in player.get_animation_list():
				if anim_name == "T-Pose" or _library.has_animation(anim_name):
					continue
				var anim := player.get_animation(anim_name).duplicate(true) as Animation
				# Le mannequin n'a pas les os « handslot » : on retire ces pistes
				for t in range(anim.get_track_count() - 1, -1, -1):
					if str(anim.track_get_path(t)).contains("handslot"):
						anim.remove_track(t)
				if anim_name in LOOPING:
					anim.loop_mode = Animation.LOOP_LINEAR
				_library.add_animation(anim_name, anim)
		scene.free()
	return _library


func _ready() -> void:
	_root = (load(MANNEQUIN) as PackedScene).instantiate() as Node3D
	_root.rotation.y = PI   # le mannequin regarde +Z
	_root.scale = Vector3.ONE * MODEL_SCALE
	add_child(_root)
	skeleton = _root.get_node(SKEL) as Skeleton3D
	_head_idx = skeleton.find_bone("head")
	_tint()
	var mod := ProportionModifier.new()
	mod.setup(skeleton, HEAD_SCALE, LEG_SCALE)
	skeleton.add_child(mod)
	_attach_helmet()
	_attach_weapon()
	_build_tree()


# --- API ---------------------------------------------------------------------------

## speed : vitesse horizontale (m/s) ; aim / crouch : 0..1.
func set_motion(speed: float, aim: float, crouch: float) -> void:
	if dead:
		return
	_tree.set("parameters/loco/blend_position", speed)
	_tree.set("parameters/aim/blend_amount", aim if speed < 3.5 else 0.0)
	_tree.set("parameters/crouch/blend_amount", crouch)
	_aim_t = aim if speed < 3.5 else 0.0


func _process(delta: float) -> void:
	if _gun == null or dead:
		return
	# Arme épaulée en visée, canon baissé sinon ; suit l'accroupissement via la hauteur du cou
	var k := 1.0 - exp(-10.0 * delta)
	var aimed := _gun.get_meta("aim", 0.0) as float
	aimed = lerpf(aimed, _aim_t, k)
	_gun.set_meta("aim", aimed)
	var neck := to_local(skeleton.global_transform * skeleton.get_bone_global_pose(_head_idx).origin)
	_gun.position = _gun.position.lerp(Vector3(0.12, neck.y - 0.12 - 0.15 * (1.0 - aimed), -0.28), k)
	_gun.rotation = Vector3(deg_to_rad(-35.0) * (1.0 - aimed), deg_to_rad(25.0) * (1.0 - aimed), 0.0)


func play_shoot() -> void:
	if not dead:
		_tree.set("parameters/shot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func play_action(anim_name: String) -> void:
	if dead:
		return
	var node := (_tree.tree_root as AnimationNodeBlendTree).get_node("act_anim") as AnimationNodeAnimation
	node.animation = anim_name
	_tree.set("parameters/act/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func play_death() -> void:
	dead = true
	_tree.set("parameters/act/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
	(((_tree.tree_root as AnimationNodeBlendTree).get_node("death") as AnimationNodeAnimation)).animation = \
		"Death_A" if randf() < 0.5 else "Death_B"
	_tree.set("parameters/life/transition_request", "dead")
	# L'arme tombe au sol à côté du corps
	if _gun:
		var tw := _gun.create_tween()
		tw.tween_property(_gun, "position", Vector3(0.45, 0.06, -0.3), 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(_gun, "rotation", Vector3(0.0, randf_range(0.6, 1.6), PI * 0.5), 0.5)


## Hauteur (globale) du cou : au-dessus, c'est un tir à la tête.
func neck_height() -> float:
	return (skeleton.global_transform * skeleton.get_bone_global_pose(_head_idx)).origin.y


# --- Construction ---------------------------------------------------------------------

func _mat(c: Color) -> StandardMaterial3D:
	if _mats.has(c):
		return _mats[c]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.85
	_mats[c] = m
	return m


func _tint() -> void:
	var f: Dictionary = FACTIONS[faction]
	for mi in skeleton.find_children("*", "MeshInstance3D", false, false):
		var mesh := mi as MeshInstance3D
		var n := String(mesh.name)
		var c: Color = f["uniform"]
		if n.contains("Head"):
			c = f["skin"]
		elif n.contains("Leg"):
			c = f["legs"]
		mesh.material_override = _mat(c)


func _bone_attach(bone: String) -> BoneAttachment3D:
	var ba := BoneAttachment3D.new()
	ba.bone_name = bone
	skeleton.add_child(ba)
	return ba


func _part(parent: Node3D, m: Mesh, pos: Vector3, c: Color, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = _mat(c)
	mi.position = pos
	mi.rotation_degrees = rot
	parent.add_child(mi)
	return mi


func _attach_helmet() -> void:
	# L'attache suit l'os de la tête, échelle comprise : on modélise pour la tête d'origine.
	var ba := _bone_attach("head")
	var c: Color = FACTIONS[faction]["helmet"]
	var dome := SphereMesh.new()
	dome.radius = 0.5
	dome.height = 0.62
	dome.is_hemisphere = true
	dome.radial_segments = 10
	dome.rings = 4
	_part(ba, dome, Vector3(0, 0.62, 0), c)
	var rim := CylinderMesh.new()
	rim.radial_segments = 10
	rim.rings = 1
	if faction == "axis":
		# Casque à jupe évasée
		rim.top_radius = 0.5
		rim.bottom_radius = 0.6
		rim.height = 0.2
		_part(ba, rim, Vector3(0, 0.55, 0), c)
	else:
		# Casque rond à bord plat
		rim.top_radius = 0.58
		rim.bottom_radius = 0.58
		rim.height = 0.04
		_part(ba, rim, Vector3(0, 0.62, 0), c)


func _attach_weapon() -> void:
	# La pose « 2 mains » KayKit tient une arbalète en travers : on fixe donc le fusil
	# au corps (épaulé vers -Z), sa position suivant la hauteur du cou dans _process().
	var gun := Node3D.new()
	gun.position = Vector3(0.12, 1.2, -0.28)
	add_child(gun)
	_gun = gun
	var dark := Color(0.18, 0.16, 0.14)
	var wood := Color(0.36, 0.24, 0.14)
	var length := 1.05 if weapon_kind == "rifle" else (0.7 if weapon_kind == "smg" else 1.25)
	var body := BoxMesh.new()
	body.size = Vector3(0.06, 0.09, length * 0.6) if weapon_kind != "mg" else Vector3(0.12, 0.14, length * 0.6)
	_part(gun, body, Vector3(0, 0, -length * 0.2), wood if weapon_kind == "rifle" else dark)
	var barrel := CylinderMesh.new()
	barrel.top_radius = 0.018 if weapon_kind != "mg" else 0.03
	barrel.bottom_radius = barrel.top_radius
	barrel.height = length * 0.5
	barrel.radial_segments = 6
	_part(gun, barrel, Vector3(0, 0.02, -length * 0.62), dark, Vector3(90, 0, 0))
	if weapon_kind == "smg":
		var mag := BoxMesh.new()
		mag.size = Vector3(0.03, 0.2, 0.05)
		_part(gun, mag, Vector3(0.04, -0.1, -0.2), dark)
	gun_tip = Marker3D.new()
	gun_tip.position = Vector3(0, 0.02, -length * 0.88)
	gun.add_child(gun_tip)


func _filter(node: AnimationNode) -> void:
	node.filter_enabled = true
	for b: String in UPPER_BONES:
		node.set_filter_path(NodePath("%s:%s" % [SKEL, b]), true)


func _anim_node(anim_name: String) -> AnimationNodeAnimation:
	var a := AnimationNodeAnimation.new()
	a.animation = anim_name
	return a


func _build_tree() -> void:
	var bt := AnimationNodeBlendTree.new()
	var loco := AnimationNodeBlendSpace1D.new()
	loco.min_space = 0.0
	loco.max_space = 5.0
	loco.add_blend_point(_anim_node("Idle_A"), 0.0, -1, "idle")
	loco.add_blend_point(_anim_node("Walking_A"), 2.0, -1, "walk")
	loco.add_blend_point(_anim_node("Running_HoldingRifle"), 4.5, -1, "run")
	bt.add_node("loco", loco)
	bt.add_node("crouch_anim", _anim_node("Crouching"))
	bt.add_node("crouch", AnimationNodeBlend2.new())
	bt.connect_node("crouch", 0, "loco")
	bt.connect_node("crouch", 1, "crouch_anim")
	bt.add_node("aim_anim", _anim_node("Ranged_2H_Aiming"))
	var aim := AnimationNodeBlend2.new()
	_filter(aim)
	bt.add_node("aim", aim)
	bt.connect_node("aim", 0, "crouch")
	bt.connect_node("aim", 1, "aim_anim")
	var shot := AnimationNodeOneShot.new()
	shot.fadein_time = 0.04
	shot.fadeout_time = 0.12
	_filter(shot)
	bt.add_node("shot", shot)
	bt.add_node("shot_anim", _anim_node("Ranged_2H_Shoot"))
	bt.connect_node("shot", 0, "aim")
	bt.connect_node("shot", 1, "shot_anim")
	var act := AnimationNodeOneShot.new()
	act.fadein_time = 0.1
	act.fadeout_time = 0.2
	bt.add_node("act", act)
	bt.add_node("act_anim", _anim_node("Hit_A"))
	bt.connect_node("act", 0, "shot")
	bt.connect_node("act", 1, "act_anim")
	var life := AnimationNodeTransition.new()
	life.add_input("alive")
	life.add_input("dead")
	life.xfade_time = 0.12
	bt.add_node("life", life)
	bt.add_node("death", _anim_node("Death_A"))
	bt.connect_node("life", 0, "act")
	bt.connect_node("life", 1, "death")
	bt.connect_node("output", 0, "life")

	_tree = AnimationTree.new()
	_root.add_child(_tree)
	_tree.root_node = NodePath("..")
	_tree.add_animation_library("", get_library())
	_tree.tree_root = bt
	_tree.active = true
	_tree.set("parameters/life/transition_request", "alive")
	# Désynchronise les soldats pour qu'ils ne respirent pas tous en même temps
	_tree.advance(randf() * 2.0)


## Corrige les proportions « chibi » du mannequin après l'animation :
## tête réduite, cuisses allongées (le tibia hérite de l'étirement), bassin relevé d'autant.
## Les modificateurs agissent sur une pose temporaire : rien ne s'accumule d'une image à l'autre.
class ProportionModifier extends SkeletonModifier3D:
	var head := -1
	var hips := -1
	var thighs: Array[int] = []
	var feet: Array[int] = []
	var head_scale := 0.5
	var leg_scale := 1.45
	var hip_raise := 0.0

	func setup(sk: Skeleton3D, h: float, l: float) -> void:
		head_scale = h
		leg_scale = l
		head = sk.find_bone("head")
		hips = sk.find_bone("hips")
		for side: String in ["l", "r"]:
			thighs.append(sk.find_bone("upperleg." + side))
			feet.append(sk.find_bone("foot." + side))
		var leg := sk.get_bone_global_rest(thighs[0]).origin.distance_to(sk.get_bone_global_rest(feet[0]).origin)
		hip_raise = leg * (leg_scale - 1.0)

	func _process_modification_with_delta(_delta: float) -> void:
		var sk := get_skeleton()
		if sk == null or head < 0:
			return
		sk.set_bone_pose_scale(head, Vector3.ONE * head_scale)
		sk.set_bone_pose_position(hips, sk.get_bone_pose_position(hips) + Vector3(0, hip_raise, 0))
		for t in thighs:
			sk.set_bone_pose_scale(t, Vector3(1.0, leg_scale, 1.0))
		for f in feet:
			sk.set_bone_pose_scale(f, Vector3(1.0, 1.0 / leg_scale, 1.0))
