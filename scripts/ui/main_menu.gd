extends Control
## Menu principal : briefing, difficulté, sensibilité, commandes.

const BRIEFING := "7 juin 1944. Les parachutistes alliés ont été dispersés dans le bocage pendant la nuit.\n\n" \
	+ "À Saint-Aubin-des-Haies, une pièce de 88 tient sous son feu la route qu'empruntent les renforts venus de la côte.\n\n" \
	+ "Votre mission : traverser les haies, reprendre la place du village et détruire le canon avant l'arrivée de la contre-attaque."

const CONTROLS := "ZQSD / WASD : se déplacer      Souris : regarder\n" \
	+ "Clic gauche : tirer      Clic droit : viser à la mire\n" \
	+ "R : recharger      1 / 2 / 3 ou molette : changer d'arme\n" \
	+ "G : grenade      E : interagir (maintenir)\n" \
	+ "Maj : sprint      C ou Ctrl : s'accroupir      Espace : sauter\n" \
	+ "Échap : pause"


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	theme = UiStyle.theme()
	var bg := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0.42, 0.3, 0.2))
	grad.set_color(1, Color(0.06, 0.06, 0.05))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.8, 1.0)
	gt.fill_to = Vector2(0.0, 0.0)
	bg.texture = gt
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 70)
	add_child(margin)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 60)
	margin.add_child(cols)

	# Colonne gauche : titre + boutons + options
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 14)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(left)
	left.add_child(UiStyle.label("OPÉRATION AUBE", 72, UiStyle.ACCENT))
	left.add_child(UiStyle.label("Normandie — juin 1944", 24, UiStyle.MUTED))
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 30)
	left.add_child(spacer)
	var start := UiStyle.button("Lancer la mission", Game.start_mission)
	left.add_child(start)
	var diff_row := HBoxContainer.new()
	diff_row.add_child(UiStyle.label("Difficulté", 18, UiStyle.MUTED))
	var diff := OptionButton.new()
	for i in Game.DIFFICULTY_NAMES.size():
		diff.add_item(Game.DIFFICULTY_NAMES[i], i)
	diff.selected = Game.difficulty
	diff.item_selected.connect(func(i: int) -> void: Game.difficulty = i)
	diff.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	diff_row.add_child(diff)
	diff_row.custom_minimum_size = Vector2(420, 0)
	left.add_child(diff_row)
	var sens := UiStyle.sensitivity_row()
	sens.custom_minimum_size = Vector2(420, 0)
	left.add_child(sens)
	var inv := CheckBox.new()
	inv.text = "Inverser l'axe vertical"
	inv.button_pressed = Game.invert_y
	inv.toggled.connect(func(on: bool) -> void: Game.invert_y = on)
	left.add_child(inv)
	if OS.get_name() != "Web":
		left.add_child(UiStyle.button("Quitter", get_tree().quit))
	start.grab_focus.call_deferred()

	# Colonne droite : briefing + commandes
	var right := PanelContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cols.add_child(right)
	var rbox := VBoxContainer.new()
	rbox.add_theme_constant_override("separation", 12)
	right.add_child(rbox)
	rbox.add_child(UiStyle.label("BRIEFING", 22, UiStyle.ACCENT))
	var brief := UiStyle.label(BRIEFING, 19)
	brief.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	brief.custom_minimum_size = Vector2(560, 0)
	rbox.add_child(brief)
	rbox.add_child(HSeparator.new())
	rbox.add_child(UiStyle.label("COMMANDES", 22, UiStyle.ACCENT))
	rbox.add_child(UiStyle.label(CONTROLS, 17, UiStyle.MUTED))
	if Game.last_result.has("victory"):
		rbox.add_child(HSeparator.new())
		var r := Game.last_result
		rbox.add_child(UiStyle.label("Dernière partie : %s — %d ennemis neutralisés" % [
			"victoire" if r["victory"] else "échec", r.get("kills", 0)], 17, UiStyle.MUTED))
