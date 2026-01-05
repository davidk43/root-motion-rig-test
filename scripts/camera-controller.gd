extends Node3D

@export var sensitivity: float = 5.0
@export var stick_sensitivity: float = 2.0

var _mouse_delta: Vector2 = Vector2.ZERO
@onready var _character: Node3D = get_tree().get_first_node_in_group("character") as Node3D

func _process(delta: float) -> void:
	if _character:
		global_position = _character.global_position

	var look_stick := Vector2(
		Input.get_action_strength("camera_right") - Input.get_action_strength("camera_left"),
		Input.get_action_strength("camera_up") - Input.get_action_strength("camera_down")
	)

	var look := Vector2.ZERO
	look += _mouse_delta * (sensitivity / 1000.0)
	look += look_stick * stick_sensitivity * delta
	_mouse_delta = Vector2.ZERO

	var min_pitch := deg_to_rad(-80.0)
	var max_pitch := deg_to_rad(80.0)
	rotation = Vector3(
		clamp(rotation.x - look.y, min_pitch, max_pitch),
		rotation.y - look.x,
		0
	)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse_delta += event.relative
