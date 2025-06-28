extends CharacterBody3D

var WALK_SPEED = 5.5
const RUN_SPEED = 9.0
const JUMP_VELOCITY = 13
const GROUND_DECELERATION = 44.0
const AIR_ACCELERATION = 1
const AIR_DECELERATION = 20.2
var frozen := true

const  gravity = 45
var sens = 0.002

@onready var highlighter = get_node("/root/WorldRoot/BlockHighlighter")
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
	#var raycast = $Camera3D/RayCast3D
	#var forward = -global_transform.basis.z.normalized()
	#var dir_name = ""
#
	#if abs(forward.x) > abs(forward.z):
		#dir_name = "East" if forward.x > 0 else "West"
	#else:
		#dir_name = "South" if forward.z > 0 else "North"
#
	#if Input.is_action_just_pressed("ui_focus_next"):
		#print("Looking toward: ", dir_name, " | Vector: ", forward)
	#
	#var block_size: float = chunk_manager.BLOCK_SIZE
	#var world_pos: Vector3 = global_transform.origin
	#var voxel_pos: Vector3i = (world_pos / block_size).floor()
#
	#var label := get_node("PlayerPos") as Label  # Adjust if nested deeper
	#if label:
		#label.text = "Voxel: (%d, %d, %d)" % [voxel_pos.x, voxel_pos.y, voxel_pos.z]



func _handle_block_interaction(button_index):
	var origin = camera_3d.global_position
	var direction = -camera_3d.global_transform.basis.z.normalized()
	var block_size = chunk_manager.BLOCK_SIZE
	var result = perform_dda(origin, direction, 10.0, block_size)
	
	if not result.hit:
		return
	
	if button_index == MOUSE_BUTTON_LEFT:
		chunk_manager.set_block_at_world_pos(result.block_pos, false)
	
	elif button_index == MOUSE_BUTTON_RIGHT:
		chunk_manager.set_block_at_world_pos(result.previous_empty, true)


func perform_dda(origin: Vector3, direction: Vector3, max_distance: float, block_size: float) -> Dictionary:
	var current = origin
	var step = direction.normalized() * 0.01  # Small step size
	var traveled = 0.0
	
	while traveled < max_distance:
		var block_coords = (current / block_size).floor() * block_size
		if chunk_manager.get_block_at_world_pos(block_coords):
			return {
				"hit": true,
				"block_pos": block_coords,
				"previous_empty": ((current - step) / block_size).floor() * block_size,
				"normal": -step.normalized().sign()
			}
		current += step
		traveled += step.length()
	
	return { "hit": false }

func _physics_process(delta):
	if frozen and chunk_manager:
		var chunk_pos: Vector3i = chunk_manager.world_to_chunk_coords(global_position)
		if chunk_manager.chunks.has(chunk_pos):
			var chunk = chunk_manager.chunks[chunk_pos]
			if chunk.is_ready():
				frozen = false
			else:
				velocity = Vector3.ZERO
				move_and_slide()
				return
		else:
			velocity = Vector3.ZERO
			move_and_slide()
			return

	if not is_on_floor():
		velocity.y -= gravity * delta

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	var input_dir = Input.get_vector("left", "right", "up", "down")
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	var SPEED: float
	if Input.is_action_pressed("run") and is_on_floor():
		SPEED = RUN_SPEED
	else:
		SPEED = WALK_SPEED

	if is_on_floor():
		if direction:
			if sign(velocity.x) != sign(direction.x):
				velocity.x = direction.x * SPEED
			else:
				velocity.x = move_toward(velocity.x, direction.x * SPEED, GROUND_DECELERATION * delta)

			if sign(velocity.z) != sign(direction.z):
				velocity.z = direction.z * SPEED
			else:
				velocity.z = move_toward(velocity.z, direction.z * SPEED, GROUND_DECELERATION * delta)
		else:
			velocity.x = move_toward(velocity.x, 0, GROUND_DECELERATION * delta)
			velocity.z = move_toward(velocity.z, 0, GROUND_DECELERATION * delta)
	else:
		if direction:
			velocity.x = move_toward(velocity.x, direction.x * SPEED, AIR_ACCELERATION * delta)
			velocity.z = move_toward(velocity.z, direction.z * SPEED, AIR_ACCELERATION * delta)
		else:
			velocity.x = move_toward(velocity.x, 0, AIR_DECELERATION * delta)
			velocity.z = move_toward(velocity.z, 0, AIR_DECELERATION * delta)

	move_and_slide()
	
#func _physics_process(delta):
	## Just apply gravity, no movement or raycasts
	#if not is_on_floor():
		#velocity.y -= gravity * delta
	#move_and_slide()

