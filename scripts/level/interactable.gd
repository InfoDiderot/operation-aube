class_name Interactable
extends Area3D
## Zone d'interaction « maintenir [E] » (pose de charge, etc.).

signal completed

var prompt := "Maintenir [E] pour interagir"
var hold_time := 3.0
var enabled := true


static func create(text: String, duration: float, radius: float) -> Interactable:
	var it := Interactable.new()
	it.prompt = text
	it.hold_time = duration
	var cs := CollisionShape3D.new()
	var s := SphereShape3D.new()
	s.radius = radius
	cs.shape = s
	it.add_child(cs)
	return it


func _ready() -> void:
	collision_layer = 0
	collision_mask = Game.LAYER_PLAYER
	body_entered.connect(_on_enter)
	body_exited.connect(_on_exit)


func _on_enter(b: Node3D) -> void:
	if b is Player:
		(b as Player).interact_target = self


func _on_exit(b: Node3D) -> void:
	if b is Player and (b as Player).interact_target == self:
		(b as Player).interact_target = null


func complete() -> void:
	enabled = false
	completed.emit()
