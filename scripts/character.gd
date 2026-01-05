extends CharacterBody3D

const JUMP_VELOCITY: float = 4.5
const DEADZONE: float = 0.15
const TURN_SPEED: float = 10.0
const WALK_STRENGTH: float = 0.3
const DIGITAL_THRESHOLD: float = 0.99
const BLEND_LERP_SPEED: float = 12.0

@onready var cam: Node3D = get_tree().get_first_node_in_group("camera") as Node3D
@onready var state: AnimationNodeStateMachinePlayback = $AnimationTree.get("parameters/playback")
@onready var anim_player: AnimationPlayer = $AnimationPlayer
@onready var anim_tree: AnimationTree = $AnimationTree

var _blend_strength: float = 0.0
var _is_crouching: bool = false
var _is_jumping: bool = false
var _was_in_jump_state: bool = false

func _ready() -> void:
	anim_player.animation_finished.connect(_on_animation_finished)
	anim_tree.animation_finished.connect(_on_animation_finished)

func _physics_process(delta: float) -> void:

	var current_state := state.get_current_node()
	var in_jump_state := current_state == "jump on spot" or current_state == "running jump"

	if not is_on_floor():
		velocity -= get_gravity() * delta

	if Input.is_action_just_pressed("player_jump") and is_on_floor():
		#velocity.y = JUMP_VELOCITY
		#state.travel("jump")  # make sure the node name matches
		print(current_state)
		$AnimationTree.set("parameters/conditions/jump", true)
		_is_jumping = true

	# Mark that we've actually entered a jump state so we don't clear early.
	if in_jump_state:
		_was_in_jump_state = true

	# Only clear jumping after we've been in a jump state and then left it.
	if _is_jumping and _was_in_jump_state and not in_jump_state:
		_is_jumping = false
		_was_in_jump_state = false
		$AnimationTree.set("parameters/conditions/jump", false)

	if Input.is_action_just_pressed("player_crouching"):
		_is_crouching = not _is_crouching

	var move := _get_move_input()
	var stick: Vector2 = move["stick"]
	var base_strength: float = move["strength"]
	var run_strength: float = Input.get_action_strength("player_run") # supports analog if bound to trigger
	var target_strength: float = 0.0
	if base_strength > 0.0:
		# For keyboard digital, base_strength is already WALK_STRENGTH or 1.0; for analog it's the stick length.
		target_strength = lerp(base_strength, 1.0, run_strength)
	_blend_strength = lerp(_blend_strength, target_strength, BLEND_LERP_SPEED * delta)

	# Camera-relative move direction on the XZ plane
	var move_dir: Vector3 = Vector3.ZERO
	if stick != Vector2.ZERO and base_strength > 0.0:
		if cam:
			var cam_basis: Basis = cam.global_transform.basis
			var cam_forward: Vector3 = -cam_basis.z
			cam_forward.y = 0.0
			cam_forward = cam_forward.normalized()
			var cam_right: Vector3 = cam_basis.x
			cam_right.y = 0.0
			cam_right = cam_right.normalized()
			move_dir = (cam_right * stick.x + cam_forward * stick.y).normalized()
		else:
			move_dir = Vector3(stick.x, 0, stick.y).normalized()

		# Smoothly face the move direction
		var target_yaw: float = atan2(-move_dir.x, -move_dir.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, TURN_SPEED * delta)

	# Drive animations using local-space move direction
	var local_dir: Vector3 = Vector3.ZERO
	if move_dir != Vector3.ZERO:
		# Preserve input magnitude for walk/run blending while using facing direction for orientation.
		local_dir = (global_transform.basis.inverse() * move_dir) * _blend_strength

	var player_moving := local_dir != Vector3.ZERO
	$AnimationTree.set("parameters/conditions/moving", player_moving and not _is_crouching and not _is_jumping)
	$AnimationTree.set("parameters/conditions/idle", not player_moving and not _is_crouching and not _is_jumping)
	$AnimationTree.set("parameters/conditions/crouched_idle", not player_moving and _is_crouching and not _is_jumping)
	$AnimationTree.set("parameters/conditions/crouched_moving", player_moving and _is_crouching and not _is_jumping)
	$AnimationTree.set("parameters/conditions/jump", _is_jumping)
	$AnimationTree.set("parameters/Moving2D/blend_position", Vector2(local_dir.x, local_dir.z))
	$AnimationTree.set("parameters/Crouching2D/blend_position", Vector2(local_dir.x, local_dir.z))

	print(_is_jumping)

	# After triggering jump, clear it so it can fire again next time.
	# if $AnimationTree.get("parameters/conditions/jump"):
	# 	$AnimationTree.set("parameters/conditions/jump", false)
	# 	_is_jumping = false

	# Apply root motion translation; ignore root motion rotation (facing driven by code)
	var root_pos: Vector3 = $AnimationTree.get_root_motion_position()
	var root_basis: Basis = Basis.IDENTITY

	velocity = global_transform.basis * (root_pos / delta)
	global_transform.basis = (global_transform.basis * root_basis).orthonormalized()

	move_and_slide()

func _on_animation_finished(anim_name: StringName) -> void:
	if anim_name == "jump on spot" or anim_name == "running jump":
		_is_jumping = false
		$AnimationTree.set("parameters/conditions/jump", false)
		print("jump finished: ", anim_name)


# Returns a Dictionary with:
#   stick: Vector2 direction (plane)
#   strength: float blend strength (walk/run), keyboard gated by run action, analog untouched
func _get_move_input() -> Dictionary:
	var raw: Vector2 = Vector2(
		Input.get_action_strength("player_right") - Input.get_action_strength("player_left"),
		Input.get_action_strength("player_up") - Input.get_action_strength("player_down")
	)
	if raw.length() < DEADZONE:
		return {"stick": Vector2.ZERO, "strength": 0.0}

	var stick: Vector2 = raw.limit_length(1.0)
	var strength: float = stick.length()

	# Only treat digital (keyboard-style) input as walk/run gated by the run action.
	var digital: bool = Input.is_physical_key_pressed(Key.KEY_W) \
		or Input.is_physical_key_pressed(Key.KEY_A) \
		or Input.is_physical_key_pressed(Key.KEY_S) \
		or Input.is_physical_key_pressed(Key.KEY_D) \
		or Input.is_physical_key_pressed(Key.KEY_UP) \
		or Input.is_physical_key_pressed(Key.KEY_DOWN) \
		or Input.is_physical_key_pressed(Key.KEY_LEFT) \
		or Input.is_physical_key_pressed(Key.KEY_RIGHT)
	if digital:
		var sprinting := Input.is_action_pressed("player_run")
		strength = 1.0 if sprinting else WALK_STRENGTH

	return {"stick": stick.normalized(), "strength": strength}
