extends CharacterBody3D

var SPEED = 15.0
const RUN_SPEED = 23.0
const JUMP_VELOCITY = 14.5 #14.5
const AIR_DECELERATION = 0.1 #0.1
const AIR_CONTROL = 0.04 # Keep this value small for smooth control

# Get the gravity from the project settings to be synced with RigidBody nodes.
var gravity = 50
var sens = 0.002

@onready var camera_3d = $Camera3D
@onready var player_arm = $Camera3D/PlayerArm
@onready var ray_cast_3d = $Camera3D/RayCast3D
@onready var hotbar = $Hotbar
@onready var arm_move = $Camera3D/PlayerArm/arm_move



@onready var item_holder = $Camera3D/PlayerArm/ItemHolder
@onready var mesh_library = preload("res://Resources/blocks.tres")


var selected = 1
var current_item_instance = null


var bobbing_amplitude = 0.2
var bobbing_frequency = 0.5
var bobbing_phase = 0.0
var bobbing_offset = Vector3.ZERO
var is_moving = false
var movement_threshold = 0.01
var original_camera_position = Vector3.ZERO
var original_arm_position = Vector3.ZERO



func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	hotbar.select(0)
	original_camera_position = camera_3d.position
	original_arm_position = player_arm.position
	update_held_item(selected)


func _unhandled_input(event):
	if event is InputEventMouseMotion:
		rotation.y -= event.relative.x * sens 
		camera_3d.rotation.x -= event.relative.y * sens
		camera_3d.rotation.x = clamp(camera_3d.rotation.x, deg_to_rad(-90), deg_to_rad(85))

func _physics_process(delta):
	# Add the gravity.
	if not is_on_floor():
		velocity.y -= gravity * delta
		
	# Handle jump.
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	if Input.is_action_just_pressed("fly_down"):
		velocity.y = -10
	# Get the input direction and handle the movement/deceleration.
	# As good practice, you should replace UI actions with custom gameplay actions.
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
		# Apply reduced speed and deceleration when in the air
		velocity.x = move_toward(velocity.x, 0, AIR_DECELERATION * delta)
		velocity.z = move_toward(velocity.z, 0, AIR_DECELERATION * delta)
	
		if direction:
			# Interpolate the velocity towards the desired direction
			velocity.x = lerp(velocity.x, direction.x * SPEED, AIR_CONTROL)
			velocity.z = lerp(velocity.z, direction.z * SPEED, AIR_CONTROL)

	is_moving = velocity.length() > movement_threshold
	apply_bobbing(delta)

	# Handle Mouse Clicks
	if Input.is_action_just_pressed("left_click"):
		if ray_cast_3d.is_colliding():
			
			if ray_cast_3d.get_collider().has_method("destroy_block"):
				ray_cast_3d.get_collider().destroy_block(ray_cast_3d.get_collision_point() - ray_cast_3d.get_collision_normal())
				animate_arm("arm_move")

				
	if Input.is_action_just_pressed("right_click"):
		if ray_cast_3d.is_colliding():
			
			if ray_cast_3d.get_collider().has_method("place_block"):
				print(ray_cast_3d.get_collision_normal(), ray_cast_3d.get_collision_point())
				ray_cast_3d.get_collider().place_block(ray_cast_3d.get_collision_point() + ray_cast_3d.get_collision_normal(), selected)
				animate_arm("arm_move")

				



	# Handle Block Selection
	if Input.is_action_just_pressed("one"):
		selected = 8
		hotbar.select(0)
		update_held_item(selected)
		
	if Input.is_action_just_pressed("two"):
		selected = 17
		hotbar.select(1)
		update_held_item(selected)
		
	if Input.is_action_just_pressed("three"):
		selected = 10
		hotbar.select(2)
		update_held_item(selected)
		
	if Input.is_action_just_pressed("four"):
		selected = 16
		hotbar.select(3)
		update_held_item(selected)

	move_and_slide()

func apply_bobbing(delta):
	# Calculate bobbing effect
	if is_moving and is_on_floor():
		bobbing_phase += delta * bobbing_frequency * SPEED
		var vertical_bob = sin(bobbing_phase) * bobbing_amplitude
		var horizontal_bob = cos(bobbing_phase * 2.0) * bobbing_amplitude * 0.5
		bobbing_offset = Vector3(horizontal_bob, vertical_bob, 0)
	else:
		bobbing_phase = 0.0
		bobbing_offset = Vector3.ZERO
	
	# Apply bobbing effect to the camera's transform
	camera_3d.position = camera_3d.position.lerp(original_camera_position + bobbing_offset, delta * 5.0)

	# Apply bobbing effect to the arm's transform
	player_arm.position = player_arm.position.lerp(original_arm_position + bobbing_offset * 0.5, delta * 5.0)  



func update_held_item(item_id):
	print(item_id)
	if current_item_instance:
		current_item_instance.queue_free()
	
	var mesh_instance = MeshInstance3D.new()
	var mesh = mesh_library.get_item_mesh(item_id)
	if mesh:
		mesh_instance.mesh = mesh
		mesh_instance.rotation_degrees = Vector3(10,30,2)
		mesh_instance.scale = Vector3(0.5,0.5,0.5)
		
		item_holder.add_child(mesh_instance)
		current_item_instance = mesh_instance
		
		

func animate_arm(animation_name: String):
	if arm_move:
		print("Playing animation: ", animation_name)
		if arm_move.has_animation(animation_name):
			arm_move.stop()
			arm_move.play(animation_name)
			arm_move.seek(0, true)  # Restart the animation from the beginning
		else:
			print("Error: Animation not found - ", animation_name)
	else:
		print("Error: animation_player is null")
