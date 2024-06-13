extends Node3D

signal request_set_block(x, y, z, block_type)

const chunk_size = Vector3(16, 16, 16)
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

var load_thread: Thread = null
var load_queue: Array = []  
var load_mutex: Mutex = Mutex.new()
var stop_thread = false

var block_update_queue: Array = []
var block_update_mutex: Mutex = Mutex.new()

# On Initial load:
func _ready():
	print("Attempting to load world with ", render_distance, " render distance.")
	mesh_library = load("res://Resources/blocks.tres")
	if mesh_library == null:
		print("Error: Mesh library could not be loaded.")
		return

	# Initialize FastNoiseLite for noise generation
	noise_generator = FastNoiseLite.new()
	noise_generator.seed = randi()
	noise_generator.noise_type = FastNoiseLite.TYPE_VALUE_CUBIC
	noise_generator.frequency = 0.02

	grid_map.mesh_library = mesh_library

	load_mutex = Mutex.new()
	block_update_mutex = Mutex.new()

	if load_mutex == null:
		print("Error: Failed to initialize load_mutex")
	if block_update_mutex == null:
		print("Error: Failed to initialize block_update_mutex")

	load_thread = Thread.new()
	load_thread.start(Callable(self, "_load_chunks"))

	# Connect the signal to a method
	connect("request_set_block", Callable(self, "_on_request_set_block"))


# Adding process_block_updates to _process function
func _process(delta):
	time_since_last_check += delta
	if time_since_last_check >= check_frequency:
		time_since_last_check = 0
		var player_position = get_player_position()
		var player_chunk = get_player_chunk(player_position)
		
		if player_chunk != current_player_chunk:
			current_player_chunk = player_chunk
			update_chunks(player_position)
	process_task_queue()
	process_block_updates()  # Add this line to process block updates
	update_metrics()

# Process block updates
func process_block_updates():
	if block_update_mutex != null:
		block_update_mutex.lock()
	else:
		print("Error: block_update_mutex is null in process_block_updates")
	var updates = block_update_queue.duplicate()
	block_update_queue.clear()
	if block_update_mutex != null:
		block_update_mutex.unlock()
	else:
		print("Error: block_update_mutex is null after unlock in process_block_updates")

	for update in updates:
		var x = update["x"]
		var y = update["y"]
		var z = update["z"]
		var block_type = update["block_type"]

		if block_type == "-1":
			grid_map.call_deferred("set_cell_item", Vector3i(x, y, z), -1)
		else:
			var block_id = mesh_library.find_item_by_name(block_type)
			if block_id != -1:
				grid_map.call_deferred("set_cell_item", Vector3i(x, y, z), block_id)


# Handle the set_block requests on the main thread
func _on_request_set_block(x: int, y: int, z: int, block_type: String):
	if block_update_mutex != null:
		block_update_mutex.lock()
	else:
		print("Error: block_update_mutex is null in _on_request_set_block")
	block_update_queue.append({"x": x, "y": y, "z": z, "block_type": block_type})
	if block_update_mutex != null:
		block_update_mutex.unlock()
	else:
		print("Error: block_update_mutex is null after unlock in _on_request_set_block")


# Return the players position
func get_player_position():
	return get_node("/root/Level/Player").global_transform.origin

# Return the players chunk coordinate
func get_player_chunk(player_position):
	return Vector3(
		int(floor(player_position.x / (chunk_size.x * 2))), 
		0,
		int(floor(player_position.z / (chunk_size.z * 2)))
	)

# This is responsible for updating chunks loaded and unloaded. 
func update_chunks(player_position):
	var player_chunk = get_player_chunk(player_position)
	var player_chunk_x = int(player_chunk.x)
	var player_chunk_z = int(player_chunk.z)
	
	var chunks_to_keep = {}
	var radius = int(floor(render_distance / 2))

	for x in range(player_chunk_x - radius, player_chunk_x + radius + 1):
		for z in range(player_chunk_z - radius, player_chunk_z + radius + 1):
			var chunk_position = Vector3(x, 0, z)
			chunks_to_keep[chunk_position] = true
			
			if not generated_chunks.has(chunk_position):
				if not is_chunk_in_load_queue(chunk_position):
					task_queue.append({"action": "load_or_generate", "chunk_position": chunk_position})
				generated_chunks[chunk_position] = true
	
	var keys_to_remove = []
	for chunk_position in generated_chunks.keys():
		if not chunks_to_keep.has(chunk_position) and not is_chunk_in_unload_queue(chunk_position):
			task_queue.append({"action": "unload", "chunk_position": chunk_position})
			keys_to_remove.append(chunk_position)
	
	for key in keys_to_remove:
		generated_chunks.erase(key)
	
	print("Chunks loaded: ", generated_chunks.size())

# This is for processing the queue of tasks.
func process_task_queue():
	var tasks_to_process = min(task_queue.size(), max_tasks_per_frame)
	
	for i in range(tasks_to_process):
		var task = task_queue.pop_front()
		
		if task["action"] == "generate":
			generate_chunk(task["chunk_position"])
		elif task["action"] == "unload":
			unload_chunk(task["chunk_position"])
		elif task["action"] == "load_or_generate":
			add_task_to_load_queue(task)

# This function handles the chunk loading in a separate thread.
# This function handles the chunk loading in a separate thread.
func _load_chunks():
	#print("_load_chunks running")
	while not stop_thread:
		if load_mutex != null:
			load_mutex.lock()
		else:
			print("Error: load_mutex is null in _load_chunks")
		if load_queue.size() > 0:
			var task = load_queue.pop_front()
			if load_mutex != null:
				load_mutex.unlock()
			else:
				print("Error: load_mutex is null after unlock in _load_chunks")
			if task["action"] == "generate":
				generate_chunk(task["chunk_position"])
			elif task["action"] == "load_or_generate":
				if not load_chunk(task["chunk_position"]):
					if load_mutex != null:
						load_mutex.lock()
					else:
						print("Error: load_mutex is null in _load_chunks (load_or_generate)")
					load_queue.append({"action": "generate", "chunk_position": task["chunk_position"]})
					if load_mutex != null:
						load_mutex.unlock()
					else:
						print("Error: load_mutex is null after unlock in _load_chunks (load_or_generate)")
		else:
			if load_mutex != null:
				load_mutex.unlock()
			else:
				print("Error: load_mutex is null after unlock in _load_chunks (empty queue)")
			await get_tree().create_timer(0.01).timeout




# Add task to the load queue
func add_task_to_load_queue(task):
	#print(" add_task_to_load_queue running")
	if load_mutex != null:
		load_mutex.lock()
	else:
		print("Error: load_mutex is null in add_task_to_load_queue")
	load_queue.append(task)
	if load_mutex != null:
		load_mutex.unlock()
	else:
		print("Error: load_mutex is null after unlock in add_task_to_load_queue")


# This is focused on the generation of chunks, using the Vector3 chunk_position passed to it.
func generate_chunk(chunk_position: Vector3):
	var chunk_data = {}
	
	for x in range(chunk_size.x):
		for z in range(chunk_size.z):
			var world_x = int(chunk_position.x * chunk_size.x + x)
			var world_z = int(chunk_position.z * chunk_size.z + z)
			
			var height = int(combined_noise(world_x, world_z) * 64) + 64  # Adjust the terrain height range
			
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
					
					# Emit the signal to set the block on the main thread.
					call_deferred("emit_signal", "request_set_block", world_x, world_y, world_z, block_type)
				
				chunk_data[Vector3i(x, y, z)] = block_type
				
	save_chunk_data(chunk_position, chunk_data)

# This is focused on unloading chunks based on the chunk_position delivered. 
func unload_chunk(chunk_position: Vector3):
	#print("unload_chunk running")
	for x in range(chunk_size.x):
		for z in range(chunk_size.z):
			for y in range(chunk_size.y):
				var world_x = int(chunk_position.x * chunk_size.x + x)
				var world_z = int(chunk_position.z * chunk_size.z + z)
				call_deferred("emit_signal", "request_set_block", world_x, y, world_z, "-1")

# Combine multiple layers of noise to create hi-fi noise. 
func combined_noise(x, z):
	var noise1 = noise_generator.get_noise_2d(x * 0.1, z * 0.1)
	var noise2 = noise_generator.get_noise_2d(x * 0.2, z * 0.2) * 0.5
	var noise3 = noise_generator.get_noise_2d(x * 0.4, z * 0.4) * 0.5
	return noise1 + noise2 + noise3

# This collates the chunk_position, and chunk_data into a single file. 
func save_chunk_data(chunk_position: Vector3, chunk_data: Dictionary):
	#print("save_chunk_data running")
	var file_path = "res://chunks/%d_%d.chunk" % [int(chunk_position.x), int(chunk_position.z)]
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if file:
		file.store_var(chunk_data)
		file.close()
	else:
		print("Error: Could not open file for writing: " + file_path)

func load_chunk(chunk_position: Vector3) -> bool:
	print("Loading chunk", chunk_position)
	var file_path = "res://chunks/%d_%d.chunk" % [int(chunk_position.x), int(chunk_position.z)]
	if FileAccess.file_exists(file_path):
		var file = FileAccess.open(file_path, FileAccess.READ)
		if file:
			var chunk_data = file.get_var()
			file.close()
			for coord in chunk_data.keys():
				var block_type = chunk_data[coord] as String
				if block_type != "":
					var world_x = int(chunk_position.x * chunk_size.x + coord.x)
					var world_y = int(coord.y)
					var world_z = int(chunk_position.z * chunk_size.z + coord.z)
					# Emit the signal to set the block on the main thread.
					call_deferred("emit_signal", "request_set_block", world_x, world_y, world_z, block_type)
			return true
		else:
			print("Error: Could not open file for reading: " + file_path)
	return false

func save_chunk(chunk_position: Vector3):
	#print("save_chunk running")
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

func is_chunk_in_load_queue(chunk_position: Vector3) -> bool:
	print("is_chunk_in_load_queue running")
	for task in task_queue:
		if task["action"] == "load_or_generate" and task["chunk_position"] == chunk_position:
			return true
	return false

func is_chunk_in_unload_queue(chunk_position: Vector3) -> bool:
	print("is_chunk_in_unload_queue running")
	for task in task_queue:
		if task["action"] == "unload" and task["chunk_position"] == chunk_position:
			return true
	return false

# Clean up the thread when the game exits
func _exit_tree():
	stop_thread = true
	if load_thread:
		load_thread.wait_to_finish()
