extends CharacterBody3D

var SPEED = 11.0
const RUN_SPEED = 30.0
const JUMP_VELOCITY = 104.5
const AIR_DECELERATION = 0.1
const AIR_CONTROL = 0.04

var gravity = 10
var sens = 0.002

@onready var camera_3d = $Camera3D
@onready var player_arm = $Camera3D/PlayerArm
@onready var ray_cast_3d = $Camera3D/RayCast3D
@onready var arm_move = $Camera3D/PlayerArm/arm_move
@onready var item_holder = $Camera3D/PlayerArm/ItemHolder
@export var BLOCK_SIZE: float = 1.0
var chunk_manager  # Must be assigned externally, e.g. from main scene

var bobbing_amplitude = 0.2
var bobbing_frequency = 0.5
var bobbing_phase = 0.0
var bobbing_offset = Vector3.ZERO
var is_moving = false
var movement_threshold = 0.01
var original_camera_position = Vector3.ZERO
var original_arm_position = Vector3.ZERO

func _ready():
	if $fps_label:
		$fps_label.text = "FPS: %d" % Engine.get_frames_per_second()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	original_camera_position = camera_3d.position
	original_arm_position = player_arm.position

func _unhandled_input(event):
	if event is InputEventMouseMotion:
		rotation.y -= event.relative.x * sens 
		camera_3d.rotation.x -= event.relative.y * sens
		camera_3d.rotation.x = clamp(camera_3d.rotation.x, deg_to_rad(-90), deg_to_rad(85))
	
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT:
			_handle_block_interaction(event.button_index)

func _process(delta):
	if $fps_label:
		$fps_label.text = "FPS: %d" % Engine.get_frames_per_second()
	
	var forward = -global_transform.basis.z.normalized()
	var dir_name = ""

	if abs(forward.x) > abs(forward.z):
		dir_name = "East" if forward.x > 0 else "West"
	else:
		dir_name = "South" if forward.z > 0 else "North"

	if Input.is_action_just_pressed("ui_focus_next"):
		print("Looking toward: ", dir_name, " | Vector: ", forward)

func _handle_block_interaction(button_index):
	ray_cast_3d.enabled = true
	ray_cast_3d.force_raycast_update()

	if not ray_cast_3d.is_colliding():
		ray_cast_3d.enabled = false
		return

	var collision_point = ray_cast_3d.get_collision_point()
	var normal = ray_cast_3d.get_collision_normal()

	if button_index == MOUSE_BUTTON_LEFT:
		var block_size = chunk_manager.BLOCK_SIZE
		var block_pos = (collision_point - normal * 0.01) / block_size
		block_pos = block_pos.floor() * block_size
		print("🪓 Breaking block at: ", block_pos)
		if chunk_manager:
			chunk_manager.set_block_at_world_pos(block_pos, false)

	elif button_index == MOUSE_BUTTON_RIGHT:
		var block_size = chunk_manager.BLOCK_SIZE
		var block_pos = (collision_point + normal * 0.2) / block_size
		block_pos = block_pos.floor() * block_size
		print("🧱 Placing block at: ", block_pos)
		if chunk_manager:
			chunk_manager.set_block_at_world_pos(block_pos, true)

	ray_cast_3d.enabled = false

func _physics_process(delta):
	if not is_on_floor():
		velocity.y -= gravity * delta

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	if Input.is_action_just_pressed("fly_down"):
		velocity.y = -10

	var input_dir = Input.get_vector("left", "right", "up", "down")
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	if Input.is_action_pressed("run") and is_on_floor():
		SPEED = RUN_SPEED
	else:
		SPEED = 10.0

	if is_on_floor():
		if direction:
			velocity.x = direction.x * SPEED
			velocity.z = direction.z * SPEED
		else:
			velocity.x = move_toward(velocity.x, 0, SPEED)
			velocity.z = move_toward(velocity.z, 0, SPEED)
	else:
		velocity.x = move_toward(velocity.x, 0, AIR_DECELERATION * delta)
		velocity.z = move_toward(velocity.z, 0, AIR_DECELERATION * delta)

		if direction:
			velocity.x = lerp(velocity.x, direction.x * SPEED, AIR_CONTROL)
			velocity.z = lerp(velocity.z, direction.z * SPEED, AIR_CONTROL)

	is_moving = velocity.length() > movement_threshold
	apply_bobbing(delta)

	move_and_slide()

func apply_bobbing(delta):
	if is_moving and is_on_floor():
		bobbing_phase += delta * bobbing_frequency * SPEED
		var vertical_bob = sin(bobbing_phase) * bobbing_amplitude
		var horizontal_bob = cos(bobbing_phase * 2.0) * bobbing_amplitude * 0.5
		bobbing_offset = Vector3(horizontal_bob, vertical_bob, 0)
	else:
		bobbing_phase = 0.0
		bobbing_offset = Vector3.ZERO

	camera_3d.position = camera_3d.position.lerp(original_camera_position + bobbing_offset, delta * 5.0)
	player_arm.position = player_arm.position.lerp(original_arm_position + bobbing_offset * 0.5, delta * 5.0)

func animate_arm(animation_name: String):
	if arm_move:
		if arm_move.has_animation(animation_name):
			arm_move.stop()
			arm_move.play(animation_name)
			arm_move.seek(0, true)
		else:
			print("Error: Animation not found - ", animation_name)
	else:
		print("Error: animation_player is null")
