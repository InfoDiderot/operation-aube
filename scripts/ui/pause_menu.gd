class_name PauseMenu
extends CanvasLayer
## Menu pause (Échap) : met l'arbre en pause, reste actif pendant la pause.

var allowed := true
var _root: Control


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.theme = UiStyle.theme()
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	box.add_child(UiStyle.label("PAUSE", 40, UiStyle.ACCENT))
	box.add_child(UiStyle.button("Reprendre", toggle))
	box.add_child(UiStyle.button("Recommencer la mission", Game.start_mission))
	box.add_child(UiStyle.button("Menu principal", Game.go_to_menu))
	box.add_child(UiStyle.sensitivity_row())
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if allowed and event.is_action_pressed("pause"):
		toggle()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	visible = not visible
	get_tree().paused = visible
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if visible else Input.MOUSE_MODE_CAPTURED
