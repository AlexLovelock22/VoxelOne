extends Node3D

@export var chunk_scene: PackedScene
var chunks = {}

var shared_noise := FastNoiseLite.new()

func _ready():
	var rng = RandomNumberGenerator.new()
	shared_noise.seed = rng.randi()
	shared_noise.frequency = 0.02

	var positions := []

	for x in range(-10, 10):
		for z in range(-10, 10):
			positions.append(Vector3i(x, 0, z))

	# Sort by distance from origin
	positions.sort_custom(_sort_by_distance_from_origin)

	for pos in positions:
		spawn_chunk(pos)


func _sort_by_distance_from_origin(a: Vector3i, b: Vector3i) -> bool:
	return a.length_squared() < b.length_squared()


func spawn_chunk(chunk_pos: Vector3i):
	if chunks.has(chunk_pos):
		return

	var chunk_instance = chunk_scene.instantiate()
	chunk_instance.chunk_manager = self

	# Logical and world offset
	chunk_instance.set_chunk_data(shared_noise, chunk_pos)
	chunk_instance.chunk_offset = chunk_pos * chunk_instance.CHUNK_SIZE

	# World position
	chunk_instance.position = chunk_pos * chunk_instance.CHUNK_SIZE * chunk_instance.BLOCK_SIZE

	add_child(chunk_instance)
	chunks[chunk_pos] = chunk_instance

	# Try generating this chunk if neighbors exist
	_try_generate_if_ready(chunk_pos)

	# Also re-check neighboring chunks — they may have been waiting on this one
	for dir in [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1)
	]:
		var neighbor_pos = chunk_pos + dir
		if chunks.has(neighbor_pos):
			var neighbor = chunks[neighbor_pos]
			if not neighbor.mesh_generated:
				_try_generate_if_ready(neighbor_pos)
			else:
				# 🔁 Re-mesh neighbor now that this chunk exists
				neighbor.generate_mesh()
		
		
	print("Spawning chunk at ", chunk_pos)  # ✅ add this


func _try_generate_if_ready(pos: Vector3i):
	if not chunks.has(pos):
		return

	var required_dirs = [
		Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
		Vector3i(0, 0, 1), Vector3i(0, 0, -1)
	]

	for dir in required_dirs:
		if not chunks.has(pos + dir):
			return  # Missing a neighbor

	var chunk = chunks[pos]
	if not chunk.mesh_generated:
		chunk.generate_mesh()

	print("Checking if chunk at", pos, "is ready to mesh")  # ✅ add this



func is_block_solid_at_world_pos(world_pos: Vector3i) -> bool:
	if chunks.is_empty():
		return false

	var any_chunk = chunks.values()[0]
	var chunk_size = any_chunk.CHUNK_SIZE

	var chunk_pos = Vector3i(
		floor(world_pos.x / chunk_size),
		0,
		floor(world_pos.z / chunk_size)
	)

	if not chunks.has(chunk_pos):
		return false

	var local_pos = world_pos - chunk_pos * chunk_size
	var chunk = chunks[chunk_pos]
	return chunk.block_map.has(local_pos)
