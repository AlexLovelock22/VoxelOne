extends Node3D

@export var chunk_scene: PackedScene
var chunks = {}

var shared_noise := FastNoiseLite.new()

func _ready():
	var rng = RandomNumberGenerator.new()
	var seed = rng.randi()
	shared_noise.seed = seed
	shared_noise.frequency = 0.02

	# Generate 3x3 chunk grid around origin
	for x in range(-10, 10):
		for z in range(-10, 10):
			spawn_chunk(Vector3i(x, 0, z))

func spawn_chunk(chunk_pos: Vector3i):
	if chunks.has(chunk_pos):
		return

	var chunk_instance = chunk_scene.instantiate()

	chunk_instance.position = chunk_pos
	chunk_instance.position = chunk_pos * chunk_instance.CHUNK_SIZE * chunk_instance.BLOCK_SIZE


	chunk_instance.set_chunk_data(shared_noise, chunk_pos)
	chunk_instance.chunk_offset = chunk_pos * chunk_instance.CHUNK_SIZE  # <- this makes noise seamless

	add_child(chunk_instance)
	chunks[chunk_pos] = chunk_instance
