class_name UiStyle
extends RefCounted
## Thème partagé des menus (palette kaki / sépia).

const BG := Color(0.09, 0.09, 0.07)
const PANEL := Color(0.14, 0.14, 0.11, 0.92)
const ACCENT := Color(0.95, 0.78, 0.4)
const TEXT := Color(0.92, 0.9, 0.82)
const MUTED := Color(0.7, 0.68, 0.6)


static func theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 20
	var normal := _box(Color(0.25, 0.26, 0.18))
	var hover := _box(Color(0.36, 0.37, 0.24))
	var pressed := _box(Color(0.5, 0.42, 0.22))
	for s: StyleBoxFlat in [normal, hover, pressed]:
		s.content_margin_left = 22
		s.content_margin_right = 22
		s.content_margin_top = 10
		s.content_margin_bottom = 10
	hover.border_color = ACCENT
	hover.set_border_width_all(2)
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("focus", "Button", hover)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color(1, 1, 1))
	t.set_color("font_color", "Label", TEXT)
	t.set_stylebox("panel", "PanelContainer", _box(PANEL, 6))
	return t


static func _box(c: Color, radius := 3) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(radius)
	s.content_margin_left = 24
	s.content_margin_right = 24
	s.content_margin_top = 20
	s.content_margin_bottom = 20
	return s


static func label(text: String, size := 20, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func button(text: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(320, 0)
	b.pressed.connect(func() -> void:
		Sfx.play("ui", -8.0)
		callback.call())
	return b


## Curseur de sensibilité souris partagé par le menu principal et la pause.
static func sensitivity_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_child(label("Sensibilité souris", 18, MUTED))
	var s := HSlider.new()
	s.min_value = 0.0006
	s.max_value = 0.006
	s.step = 0.0001
	s.value = Game.mouse_sensitivity
	s.custom_minimum_size = Vector2(220, 24)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.value_changed.connect(func(v: float) -> void: Game.mouse_sensitivity = v)
	row.add_child(s)
	return row
