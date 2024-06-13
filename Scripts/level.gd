extends Node3D

var chunk_size = Vector3(16, 32, 16)
var render_distance = 24

var noise_generator: FastNoiseLite
@export var mesh_library: MeshLibrary
@onready var grid_map: GridMap = $GridMap

@onready var chunks_loaded_label = $Player/chunks_loaded_label
@onready var player_position_label = $Player/player_position_label
@onready var chunk_position_label = $Player/chunk_position_label
@onready var queue_length_label = $Player/queue_length_label

var generated_chunks = {}
var current_player_chunk = Vector3(-999, 0, -999)
var check_frequency = 0.5
var time_since_last_check = 0

var task_queue = []
var max_tasks_per_frame = 1

# Define the chunk visualization mesh and instance
var chunk_visualization_mesh: ArrayMesh = null
var chunk_visualization_instance: MeshInstance3D = null

func _ready():
	mesh_library = load("res://Resources/blocks.tres")
	if mesh_library == null:
		print("Error: Mesh library could not be loaded.")
		return

	noise_generator = FastNoiseLite.new()
	noise_generator.seed = randi()
	noise_generator.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH

	grid_map.mesh_library = mesh_library

	# Create ArrayMesh for chunk visualization
	chunk_visualization_mesh = ArrayMesh.new()
	chunk_visualization_instance = MeshInstance3D.new()
	chunk_visualization_instance.mesh = chunk_visualization_mesh
	add_child(chunk_visualization_instance)

func _process(delta):
	time_since_last_check += delta
	if time_since_last_check >= check_frequency:
		time_since_last_check = 0
		var player_position = get_player_position()
		var player_chunk = get_player_chunk(player_position)
		
		if player_chunk != current_player_chunk:
			current_player_chunk = player_chunk
			#print("Updating chunks... Player Position: ", player_position, " Player Chunk: ", player_chunk)
			update_chunks(player_position)

	process_task_queue()
	update_metrics()
	#update_chunk_visualization()

func get_player_position():
	return get_node("/root/Level/Player").global_transform.origin

func get_player_chunk(player_position):
	# Adjusting player position to align with chunk size
	return Vector3(
		int(floor(player_position.x / (chunk_size.x * 2))),
		0,
		int(floor(player_position.z / (chunk_size.z * 2)))
	)

func update_chunks(player_position):
	var player_chunk = get_player_chunk(player_position)
	var player_chunk_x = int(player_chunk.x)
	var player_chunk_z = int(player_chunk.z)
	
	#print("Player Position during update: ", player_position, " Player Chunk: ", player_chunk)

	var chunks_to_keep = {}
	var radius = int(floor(render_distance / 2))

	for x in range(player_chunk_x - radius, player_chunk_x + radius + 1):
		for z in range(player_chunk_z - radius, player_chunk_z + radius + 1):
			var chunk_position = Vector3(x, 0, z)
			chunks_to_keep[chunk_position] = true
			if not generated_chunks.has(chunk_position):
				if not load_chunk(chunk_position):
					#print("Generating chunk at: ", chunk_position, " for player chunk: ", player_chunk)
					task_queue.append({"action": "generate", "chunk_position": chunk_position})
				generated_chunks[chunk_position] = true

	var keys_to_remove = []
	for chunk_position in generated_chunks.keys():
		if not chunks_to_keep.has(chunk_position) and not is_chunk_in_unload_queue(chunk_position):
			task_queue.append({"action": "unload", "chunk_position": chunk_position})
			keys_to_remove.append(chunk_position)
	
	for key in keys_to_remove:
		generated_chunks.erase(key)
	
	print("Chunks loaded: ", generated_chunks.size())

func process_task_queue():
	var tasks_to_process = min(task_queue.size(), max_tasks_per_frame)
	for i in range(tasks_to_process):
		var task = task_queue.pop_front()
		if task["action"] == "generate":
			generate_chunk(task["chunk_position"])
		elif task["action"] == "unload":
			unload_chunk(task["chunk_position"])

func generate_chunk(chunk_position: Vector3):
	#print("Generating chunk at: ", chunk_position, " Player Position during generation: ", get_player_position())
	var chunk_data = {}
	for x in range(chunk_size.x):
		for z in range(chunk_size.z):
			var world_x = int(chunk_position.x * chunk_size.x + x)
			var world_z = int(chunk_position.z * chunk_size.z + z)
			var height = int(combined_noise(world_x, world_z) * 25) + 15
			for y in range(chunk_size.y):
				var world_y = int(y)
				var block_type = ""
				if world_y <= height:
					if noise_generator.get_noise_3d(world_x * 0.1, world_y * 0.1, world_z * 0.1) < 0.5:
						block_type = "Grass"
					elif world_y < height - 3:
						block_type = "Dirt"
					else:
						block_type = "Stone"
					set_block(world_x, world_y, world_z, block_type)
				chunk_data[Vector3i(x, y, z)] = block_type
	save_chunk_data(chunk_position, chunk_data)

func unload_chunk(chunk_position: Vector3):
	#print("Unloading chunk at: ", chunk_position, " Player Position: ", get_player_position())
	for x in range(chunk_size.x):
		for z in range(chunk_size.z):
			for y in range(chunk_size.y):
				var world_x = int(chunk_position.x * chunk_size.x + x)
				var world_z = int(chunk_position.z * chunk_size.z + z)
				grid_map.set_cell_item(Vector3i(world_x, y, world_z), -1)

func combined_noise(x, z):
	var noise1 = noise_generator.get_noise_2d(x * 0.1, z * 0.1)
	var noise2 = noise_generator.get_noise_2d(x * 0.2, z * 0.2) * 0.5
	var noise3 = noise_generator.get_noise_2d(x * 0.4, z * 0.4) * 0.25
	return noise1 + noise2 + noise3

func set_block(x: int, y: int, z: int, block_type: String):
	if mesh_library == null:
		print("Error: Mesh library is not loaded.")
		return
	
	var block_id = mesh_library.find_item_by_name(block_type)
	if block_id == -1:
		print("Error: Block type", block_type, "not found in mesh library.")
		return
	
	grid_map.set_cell_item(Vector3i(x, y, z), block_id)

func save_chunk_data(chunk_position: Vector3, chunk_data: Dictionary):
	var file_path = "res://chunks/%d_%d.chunk" % [int(chunk_position.x), int(chunk_position.z)]
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if file:
		file.store_var(chunk_data)
		file.close()
	else:
		print("Error: Could not open file for writing: " + file_path)

func load_chunk(chunk_position: Vector3) -> bool:
	var file_path = "res://chunks/%d_%d.chunk" % [int(chunk_position.x), int(chunk_position.z)]
	if FileAccess.file_exists(file_path):
		var file = FileAccess.open(file_path, FileAccess.READ)
		if file:
			var chunk_data = file.get_var()
			file.close()
			for coord in chunk_data.keys():
				var block_type = chunk_data[coord]
				if block_type != "":
					var world_x = int(chunk_position.x * chunk_size.x + coord.x)
					var world_y = int(coord.y)
					var world_z = int(chunk_position.z * chunk_size.z + coord.z)
					set_block(world_x, world_y, world_z, block_type)
			#print("Chunk loaded at: ", chunk_position, " Player Position: ", get_player_position())
			return true
		else:
			print("Error: Could not open file for reading: " + file_path)
	return false

func save_chunk(chunk_position: Vector3):
	var chunk_data = {}
	for x in range(chunk_size.x):
		for z in range(chunk_size.z):
			for y in range(chunk_size.y):
				var world_x = int(chunk_position.x * chunk_size.x + x)
				var world_z = int(chunk_position.z * chunk_size.z + z)
				var block_id = grid_map.get_cell_item(Vector3i(world_x, y, world_z))
				if block_id != -1:
					var block_type = mesh_library.get_item_name(block_id)
					chunk_data[Vector3i(x, y, z)] = block_type
				else:
					chunk_data[Vector3i(x, y, z)] = ""
	save_chunk_data(chunk_position, chunk_data)

func update_metrics():
	var player_position = get_player_position()
	var player_chunk = get_player_chunk(player_position)
	player_position_label.text = "Player Position: (%.2f, %.2f, %.2f)" % [player_position.x, player_position.y, player_position.z]
	chunk_position_label.text = "Player Chunk: (%d, %d, %d)" % [player_chunk.x, player_chunk.y, player_chunk.z]
	chunks_loaded_label.text = "Chunks Loaded: %d" % generated_chunks.size()
	queue_length_label.text = "Queue Length: %d" % task_queue.size()


func is_chunk_in_unload_queue(chunk_position: Vector3) -> bool:
	for task in task_queue:
		if task["action"] == "unload" and task["chunk_position"] == chunk_position:
			return true
	return false
