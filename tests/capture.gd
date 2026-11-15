extends Node
## Outil de capture (dev) : points de vue fixes -> PNG pour vérifier le rendu.
## SHOT_DIR=/chemin xvfb-run -a godot --path . --rendering-driver opengl3 res://tests/capture.tscn
var views := [
	["squad", Vector3(0, 0.1, 96), 180.0, -4.0, false, 0.0],
	# nom, position, lacet, tangage, visée, ennemis actifs (s)
	["street", Vector3(0, 0.1, 44), -10.0, 6.0, false, 0.0],
	["square_ads", Vector3(0, 0.1, 9), 0.0, 1.5, true, 0.0],
	["combat", Vector3(1, 0.1, 86), 0.0, 0.0, false, 3.0],
	["thompson", Vector3(-30, 0.1, -2), -90.0, 2.0, false, 0.0],
]
func _ready() -> void:
	var mission: Node3D = load("res://scenes/mission.tscn").instantiate()
	get_tree().root.add_child.call_deferred(mission)
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().current_scene = mission
	var player: Player = mission.get("player")
	player.health = 1e6
	for a in mission.get("allies"):
		(a as Node).set_physics_process(false)
	var dir := OS.get_environment("SHOT_DIR")
	for v in views:
		for e in get_tree().get_nodes_in_group("enemy"):
			e.set_physics_process(v[5] > 0.0)
		player.global_position = v[1]
		if v[0] == "squad":
			for a in mission.get("allies"):
				var al := a as Ally
				al.global_position = v[1] + Vector3(-1.5 if al.slot.x < 0.0 else 1.6, 0, 4.5)
				al.rotation.y = 0.3 if al.slot.x < 0.0 else -0.4
				al.model.set_motion(0.0, 0.0, 0.0)
		player.rotation.y = deg_to_rad(v[2])
		player.head.rotation.x = deg_to_rad(v[3])
		if v[0] == "thompson":
			player.switch_to(1)
		if v[4]:
			Input.action_press("aim")
		var frames := 40 + int(v[5] * 60.0)
		for i in frames:
			if v[5] > 0.0 and i == frames - 6:
				player.test_trigger = true
			await get_tree().process_frame
		player.test_trigger = false
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s/%s.png" % [dir, v[0]])
		Input.action_release("aim")
		print("saved ", v[0])
	get_tree().quit()
