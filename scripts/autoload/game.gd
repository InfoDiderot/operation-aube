extends Node
## Autoload « Game » : réglages, actions d'entrée, statistiques et changements de scène.

signal noise_made(position: Vector3, radius: float)

const MENU_SCENE := "res://scenes/main_menu.tscn"
const MISSION_SCENE := "res://scenes/mission.tscn"
const DIFFICULTY_NAMES := ["Recrue", "Soldat", "Vétéran"]

# Couches physiques (valeurs de bits, voir project.godot)
const LAYER_WORLD := 1
const LAYER_PLAYER := 2
const LAYER_ENEMY := 4
const LAYER_INTERACT := 8
const LAYER_ALLY := 16

var difficulty := 1
var mouse_sensitivity := 0.0022  # radians par pixel
var invert_y := false
var quality := 1            # 0 = basse (sans brume volumétrique, herbe réduite), 1 = haute
var stats: Dictionary = {}
var checkpoint := 0         # 0 = début ; 1 = village ; 2 = place prise ; 3 = canon détruit
var last_result: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input()
	reset_stats()


func reset_stats() -> void:
	stats = {"shots": 0, "hits": 0, "kills": 0, "headshots": 0, "time": 0.0, "damage_taken": 0.0, "deaths": 0}


## Multiplicateur appliqué à la précision des ennemis.
func enemy_accuracy_mult() -> float:
	return [0.6, 1.0, 1.35][difficulty]


## Multiplicateur appliqué aux dégâts infligés par les ennemis.
func enemy_damage_mult() -> float:
	return [0.55, 1.0, 1.5][difficulty]


## Bruit audible par l'IA (tir, explosion) : les ennemis dans le rayon viennent voir.
func make_noise(pos: Vector3, radius: float) -> void:
	noise_made.emit(pos, radius)


func start_mission() -> void:
	reset_stats()
	checkpoint = 0
	get_tree().paused = false
	get_tree().change_scene_to_file(MISSION_SCENE)


## Recharge la mission au dernier point de contrôle (statistiques conservées).
func retry_from_checkpoint() -> void:
	stats["deaths"] = int(stats.get("deaths", 0)) + 1
	get_tree().paused = false
	get_tree().change_scene_to_file(MISSION_SCENE)


func go_to_menu() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(MENU_SCENE)


# --- Entrées -----------------------------------------------------------------
# Touches *physiques* : la même position donne ZQSD sur AZERTY et WASD sur QWERTY.
func _setup_input() -> void:
	_keys("move_forward", [KEY_W, KEY_UP])
	_keys("move_back", [KEY_S, KEY_DOWN])
	_keys("move_left", [KEY_A, KEY_LEFT])
	_keys("move_right", [KEY_D, KEY_RIGHT])
	_keys("jump", [KEY_SPACE])
	_keys("sprint", [KEY_SHIFT])
	_keys("crouch", [KEY_C, KEY_CTRL])
	_keys("reload", [KEY_R])
	_keys("interact", [KEY_E, KEY_F])
	_keys("grenade", [KEY_G])
	_keys("weapon_1", [KEY_1])
	_keys("weapon_2", [KEY_2])
	_keys("weapon_3", [KEY_3])
	_keys("pause", [KEY_ESCAPE, KEY_P])
	_mouse("fire", MOUSE_BUTTON_LEFT)
	_mouse("aim", MOUSE_BUTTON_RIGHT)
	_mouse("weapon_next", MOUSE_BUTTON_WHEEL_DOWN)
	_mouse("weapon_prev", MOUSE_BUTTON_WHEEL_UP)


func _keys(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for k: int in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


func _mouse(action: String, button: MouseButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)
