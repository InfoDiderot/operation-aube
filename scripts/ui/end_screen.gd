class_name EndScreen
extends CanvasLayer
## Écran de fin : victoire ou mort, statistiques, rejouer.


func show_result(r: Dictionary) -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.theme = UiStyle.theme()
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.05, 0.04, 0.82)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)

	var victory: bool = r.get("victory", false)
	box.add_child(UiStyle.label("MISSION ACCOMPLIE" if victory else "MORT AU COMBAT", 44,
		UiStyle.ACCENT if victory else Color(0.9, 0.35, 0.3)))
	box.add_child(UiStyle.label("Opération Aube — difficulté : %s" % Game.DIFFICULTY_NAMES[int(r.get("difficulty", 1))], 18, UiStyle.MUTED))
	var shots: int = r.get("shots", 0)
	var hits: int = r.get("hits", 0)
	var t: float = r.get("time", 0.0)
	var lines := [
		"Temps : %d min %02d s" % [int(t) / 60, int(t) % 60],
		"Ennemis neutralisés : %d (dont %d tirs à la tête)" % [r.get("kills", 0), r.get("headshots", 0)],
		"Précision : %d %% (%d / %d)" % [roundi(100.0 * hits / maxf(shots, 1.0)), hits, shots],
		"Dégâts subis : %d" % int(r.get("damage_taken", 0.0)),
		"Morts : %d" % (int(r.get("deaths", 0)) + (0 if victory else 1)),
	]
	for line: String in lines:
		box.add_child(UiStyle.label(line, 20))
	var sep := HSeparator.new()
	box.add_child(sep)
	if not victory and Game.checkpoint > 0:
		var resume := UiStyle.button("Reprendre au point de contrôle", Game.retry_from_checkpoint)
		box.add_child(resume)
		resume.grab_focus.call_deferred()
	box.add_child(UiStyle.button("Recommencer la mission", Game.start_mission))
	box.add_child(UiStyle.button("Menu principal", Game.go_to_menu))
