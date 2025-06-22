
extends Node3D

@export var chunk_scene: PackedScene
var chunks = {}
var shared_noise := FastNoiseLite.new()
var pending_mesh := {}

const log_path = "user://chunk_debug.log"
var log_buffer := []
var log_thread: Thread = Thread.new()
var log_mutex := Mutex.new()
var stop_thread := false


func _ready():
	_clear_log_file()
	log_thread = Thread.new()
	log_thread.start(_flush_log_buffer)

	_initialize_noise()
	var positions := _generate_positions()

	for pos in positions:
		_spawn_chunk(pos)

	for pos in positions:
		_try_generate_if_ready(pos)

	_retry_pending_mesh()

	stop_thread = true
	log_thread.wait_to_finish()

func _clear_log_file():
	var file = FileAccess.open(log_path, FileAccess.WRITE)
	file.store_line("=== Chunk Log Start ===")
	file.close()

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

	var quadrant = _get_quadrant(chunk_pos)
	_log("🧱 Spawned chunk at: %s [%s]" % [chunk_pos, quadrant])

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
	if not chunks.has(pos):
		_log("❌ Attempted to mesh non-existent chunk: %s" % pos)
		return

	for dir in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
		if not chunks.has(pos + dir):
			_log("⏳ Delaying mesh gen for %s, missing neighbor at %s" % [pos, pos + dir])
			pending_mesh[pos] = true
			return

	_log("✅ All neighbors ready for %s → meshing now." % pos)
	var chunk = chunks[pos]
	chunk.generate_mesh()
	_log("✔️ Mesh generated for chunk %s" % pos)

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
			_log("🔁 Retried and meshed chunk: %s" % pos)
			completed.append(pos)

	for pos in completed:
		pending_mesh.erase(pos)

func is_block_solid_at_world_pos(world_pos: Vector3i) -> bool:
	if chunks.is_empty():
		_log("⚠️ Chunks empty during solid check for: %s" % world_pos)
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
		_log("🚫 No chunk at %s (from world pos %s)" % [chunk_pos, world_pos])
		return false

	var chunk = chunks[chunk_pos]
	var solid = chunk.block_map.has(local_pos)
	_log("🔍 %s in chunk %s at local %s → solid: %s" % [world_pos, chunk_pos, local_pos, solid])
	return solid


# --- Buffered logging ---
func _log(msg: String):
	log_mutex.lock()
	log_buffer.append(msg)
	log_mutex.unlock()

func _flush_log_buffer(userdata=null):
	while not stop_thread:
		log_mutex.lock()
		var pending = log_buffer.duplicate()
		log_buffer.clear()
		log_mutex.unlock()

		if pending.size() > 0:
			var file = FileAccess.open(log_path, FileAccess.READ_WRITE)
			file.seek_end()
			for line in pending:
				file.store_line(line)
			file.close()

		# Avoid locking main thread
		OS.delay_msec(50)
