
extends Node3D

@export var chunk_scene: PackedScene
var chunks = {}
var shared_noise := FastNoiseLite.new()
var pending_mesh := {}



var chunk_thread: Thread
const log_path = "user://chunk_debug.log"
var log_buffer := []
var log_thread: Thread = Thread.new()
var log_mutex := Mutex.new()
var stop_thread := false
const CHUNK_SIZE := 16
@export var BLOCK_SIZE: float = 1.0

func _ready():
	chunk_thread = Thread.new()
	chunk_thread.start(Callable(self, "_threaded_chunk_load"))

	# ⏳ Wait until the player’s starting chunk is loaded
	var player_chunk_pos := Vector3i(0, 0, 0)
	while not chunks.has(player_chunk_pos):
		await get_tree().process_frame

	# Once the chunk under the player exists, let normal game logic proceed
	_retry_pending_mesh()

	stop_thread = true
	log_thread.wait_to_finish()


func _threaded_chunk_load(userdata = null):
	var positions := _generate_positions()

	for pos in positions:
		call_deferred("_spawn_chunk", pos)
		await get_tree().process_frame  # Spread spawning over time

	await get_tree().process_frame  # Let scene settle

	for pos in positions:
		_try_generate_if_ready(pos)
		await get_tree().process_frame  # Spread meshing over time

func _initialize_noise():
	var rng = RandomNumberGenerator.new()
	shared_noise.seed = rng.randi()
	shared_noise.frequency = 0.02

func _generate_positions() -> Array:
	var positions := []
	for x in range(-10, 10):
		for z in range(-10, 10):
			positions.append(Vector3i(x, 0, z))
	positions.sort_custom(_sort_by_distance_from_origin)
	return positions

func _sort_by_distance_from_origin(a: Vector3i, b: Vector3i) -> bool:
	return a.length_squared() < b.length_squared()


func _threaded_spawn_and_generate_chunks(positions: Array):
	# This is the only threaded part, only doing non-scene work
	for pos in positions:
		call_deferred("_spawn_chunk", pos)

	await get_tree().process_frame  # wait one frame to ensure chunks added
	for pos in positions:
		_try_generate_if_ready(pos)

	_retry_pending_mesh()


func _spawn_chunk(chunk_pos: Vector3i):
	if chunks.has(chunk_pos):
		return

	var chunk_instance = chunk_scene.instantiate()
	chunk_instance.chunk_manager = self
	chunk_instance.set_chunk_data(shared_noise, chunk_pos)
	chunk_instance.chunk_offset = chunk_pos * chunk_instance.CHUNK_SIZE
	chunk_instance.position = chunk_pos * chunk_instance.CHUNK_SIZE * chunk_instance.BLOCK_SIZE

	add_child(chunk_instance)
	chunks[chunk_pos] = chunk_instance

func _threaded_generate_chunk(chunk_pos: Vector3i, chunk_instance: Node):
	chunk_instance.generate_chunk()
	call_deferred("_finalize_chunk", chunk_pos, chunk_instance)

func _finalize_chunk(chunk_pos: Vector3i, chunk_instance: Node):
	add_child(chunk_instance)

	var quadrant = _get_quadrant(chunk_pos)
	# _log("🧱 Spawned chunk at: %s [%s]" % [chunk_pos, quadrant])

	_try_generate_if_ready(chunk_pos)


func _get_quadrant(pos: Vector3i) -> String:
	if pos.x >= 0 and pos.z >= 0:
		return "SE"
	elif pos.x < 0 and pos.z >= 0:
		return "SW"
	elif pos.x < 0 and pos.z < 0:
		return "NW"
	else:
		return "NE"

func _try_generate_if_ready(pos: Vector3i):
	for dir in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
		if not chunks.has(pos + dir):
			pending_mesh[pos] = true
			return

	var chunk = chunks[pos]
	chunk.generate_mesh()


func _retry_pending_mesh():
	var completed := []
	for pos in pending_mesh.keys():
		var ready = true
		for dir in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
			if not chunks.has(pos + dir):
				ready = false
				break
		if ready:
			var chunk = chunks[pos]
			chunk.generate_mesh()
			#_log("🔁 Retried and meshed chunk: %s" % pos)
			completed.append(pos)

	for pos in completed:
		pending_mesh.erase(pos)

func is_block_solid_at_world_pos(world_pos: Vector3i) -> bool:
	if chunks.is_empty():
		#_log("⚠️ Chunks empty during solid check for: %s" % world_pos)
		return false

	var any_chunk = chunks.values()[0]
	var chunk_size = any_chunk.CHUNK_SIZE

	# Explicit float floor then cast to int to prevent quadrant edge issues
	var chunk_x = int(floor(float(world_pos.x) / chunk_size))
	var chunk_y = int(floor(float(world_pos.y) / chunk_size))
	var chunk_z = int(floor(float(world_pos.z) / chunk_size))
	var chunk_pos = Vector3i(chunk_x, chunk_y, chunk_z)

	var local_pos = world_pos - chunk_pos * chunk_size

	if not chunks.has(chunk_pos):
		#_log("🚫 No chunk at %s (from world pos %s)" % [chunk_pos, world_pos])
		return false

	var chunk = chunks[chunk_pos]
	var solid = chunk.block_map.has(local_pos)
	#_log("🔍 %s in chunk %s at local %s → solid: %s" % [world_pos, chunk_pos, local_pos, solid])
	return solid


func set_block_at_world_pos(world_pos: Vector3, place: bool) -> void:
	var chunk_size := 16

	# Correct 3D chunk coordinate calculation (including Y)
	var chunk_coords = Vector3i(
		floori(world_pos.x / chunk_size),
		floori(world_pos.y / chunk_size),
		floori(world_pos.z / chunk_size)
	)

	# Local position within the chunk
	var local_pos = Vector3i(
		int(world_pos.x) % chunk_size,
		int(world_pos.y) % chunk_size,
		int(world_pos.z) % chunk_size
	)

	# Handle negative world coords
	if local_pos.x < 0:
		local_pos.x += chunk_size
	if local_pos.y < 0:
		local_pos.y += chunk_size
	if local_pos.z < 0:
		local_pos.z += chunk_size

	#print("Requested %s at world %s → chunk %s local %s" % [(place if place else "BREAK"), world_pos, chunk_coords, local_pos])

	# Ensure chunk exists
	if not chunks.has(chunk_coords):
		print("❌ No chunk found at %s" % chunk_coords)
		return

	var chunk = chunks[chunk_coords]

	if place:
		chunk.block_map[local_pos] = true

	else:
		if chunk.block_map.has(local_pos):
			chunk.block_map.erase(local_pos)
			
		else:
			print("⚠️ Tried to remove nonexistent block at %s in chunk %s" % [local_pos, chunk_coords])

	# Always update the current chunk's mesh
	chunk._generate_visible_mesh()

	# --- Border logic for X and Z neighbors ---
	var neighbor_directions = []

	if local_pos.x == 0:
		neighbor_directions.append(Vector3i(-1, 0, 0))
	elif local_pos.x == chunk_size - 1:
		neighbor_directions.append(Vector3i(1, 0, 0))

	if local_pos.z == 0:
		neighbor_directions.append(Vector3i(0, 0, -1))
	elif local_pos.z == chunk_size - 1:
		neighbor_directions.append(Vector3i(0, 0, 1))

	# Regenerate neighbor meshes if on edge
	for dir in neighbor_directions:
		var neighbor_coords = chunk_coords + dir
		if chunks.has(neighbor_coords):
			chunks[neighbor_coords]._generate_visible_mesh()
			#print("Updated neighbor chunk mesh at", neighbor_coords)


func get_block_at_world_pos(world_pos: Vector3) -> bool:
	var block_size = BLOCK_SIZE
	var chunk_size = CHUNK_SIZE

	var chunk_pos = Vector3i(
		floor(world_pos.x / (chunk_size * block_size)),
		0,
		floor(world_pos.z / (chunk_size * block_size))
	)

	if not chunks.has(chunk_pos):
		return false

	var local_pos = world_pos - (chunk_pos * chunk_size * block_size)
	var block_coords = Vector3i(
		floor(local_pos.x / block_size),
		floor(world_pos.y / block_size),
		floor(local_pos.z / block_size)
	)

	return chunks[chunk_pos].block_map.has(block_coords)

func world_to_chunk_coords(world_pos: Vector3) -> Vector3i:
	var chunk_size = chunk_scene.instantiate().CHUNK_SIZE
	var block_size = chunk_scene.instantiate().BLOCK_SIZE
	var chunk_world_scale = chunk_size * block_size
	return Vector3i(
		floor(world_pos.x / chunk_world_scale),
		0,
		floor(world_pos.z / chunk_world_scale)
	)
	
func is_chunk_ready(world_pos: Vector3) -> bool:
	var chunk_coords = world_to_chunk_coords(world_pos)
	if not chunks.has(chunk_coords):
		return false
	var chunk = chunks[chunk_coords]
	return chunk.is_meshed
