extends Node3D

@export var CHUNK_SIZE: int = 16
@export var BLOCK_SIZE: float = 1.0

var noise: FastNoiseLite
var chunk_offset: Vector3i
var block_map: Dictionary = {}

func set_chunk_data(p_noise: FastNoiseLite, p_offset: Vector3i):
	noise = p_noise
	chunk_offset = p_offset

func _ready():
	generate_chunk()

func generate_chunk():
	_generate_block_map()
	_generate_visible_mesh()

func _generate_block_map():
	if noise == null:
		push_error("Noise generator not set before block map generation!")
		return

	for x in range(CHUNK_SIZE):
		for z in range(CHUNK_SIZE):
			var world_x = chunk_offset.x + x
			var world_z = chunk_offset.z + z
			var height = int(noise.get_noise_2d(world_x, world_z) * CHUNK_SIZE / 2.0) + CHUNK_SIZE / 2
			for y in range(height):
				block_map[Vector3i(x, y, z)] = true
				
func _generate_visible_mesh():
	var mesh = ArrayMesh.new()
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)

	var vertices = PackedVector3Array()
	var normals = PackedVector3Array()
	var uvs = PackedVector2Array()
	var indices = PackedInt32Array()
	var index_offset = 0

	# Directions to check for face exposure
	var directions = [
		{ "dir": Vector3i(0, 1, 0), "normal": Vector3.UP,    "u": Vector3(1, 0, 0), "v": Vector3(0, 0, 1) },  # Top
		{ "dir": Vector3i(0, -1, 0), "normal": Vector3.DOWN, "u": Vector3(1, 0, 0), "v": Vector3(0, 0, -1) }, # Bottom
		{ "dir": Vector3i(1, 0, 0), "normal": Vector3.RIGHT, "u": Vector3(0, 1, 0), "v": Vector3(0, 0, 1) },  # Right
		{ "dir": Vector3i(-1, 0, 0), "normal": Vector3.LEFT, "u": Vector3(0, 1, 0), "v": Vector3(0, 0, -1) }, # Left
		{ "dir": Vector3i(0, 0, 1), "normal": Vector3.FORWARD, "u": Vector3(1, 0, 0), "v": Vector3(0, 1, 0) }, # Forward
		{ "dir": Vector3i(0, 0, -1), "normal": Vector3.BACK,   "u": Vector3(-1, 0, 0), "v": Vector3(0, 1, 0) }, # Back
	]

	for y in range(CHUNK_SIZE):
		for z in range(CHUNK_SIZE):
			for x in range(CHUNK_SIZE):
				var pos = Vector3i(x, y, z)
				if not block_map.has(pos):
					continue

				for face in directions:
					var dir = face["dir"]
					var neighbor = pos + dir
					if block_map.has(neighbor):
						continue # Face is not exposed

					var normal = face["normal"]
					var u = face["u"] * BLOCK_SIZE
					var v = face["v"] * BLOCK_SIZE
					var p = pos * BLOCK_SIZE

					# Offset top/right/forward face vertices
					if dir == Vector3i(0, 1, 0): p += Vector3(0, BLOCK_SIZE, 0)
					if dir == Vector3i(1, 0, 0): p += Vector3(BLOCK_SIZE, 0, 0)
					if dir == Vector3i(0, 0, 1): p += Vector3(0, 0, BLOCK_SIZE)

					# Define quad
					var v0 = p
					var v1 = p + u
					var v2 = p + u + v
					var v3 = p + v

					# Append vertices
					vertices.append_array([v0, v1, v2, v3])
					normals.append_array([normal, normal, normal, normal])
					uvs.append_array([
						Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)
					])

					# Indices
					indices.append_array([
						index_offset, index_offset + 1, index_offset + 2,
						index_offset, index_offset + 2, index_offset + 3
					])
					index_offset += 4

	# Commit mesh
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	$MeshInstance3D.mesh = mesh

	# Collision
	var collider = StaticBody3D.new()
	var collision_shape = CollisionShape3D.new()
	var shape = ConcavePolygonShape3D.new()
	var faces = PackedVector3Array()
	for i in indices:
		faces.append(vertices[i])
	shape.set_faces(faces)
	collision_shape.shape = shape
	collider.add_child(collision_shape)
	add_child(collider)

	print("Chunk generated with %d vertices, %d indices, and 1 collision shape" % [vertices.size(), indices.size()])



func _add_face(pos: Vector3i, normal: Vector3, vert_idx: Array, vertices, normals, uvs, indices):
	var base_index = vertices.size()
	var p = pos * BLOCK_SIZE
	var s = BLOCK_SIZE

	var v = [
		p + Vector3(0, 0, 0) * s, p + Vector3(1, 0, 0) * s,
		p + Vector3(1, 1, 0) * s, p + Vector3(0, 1, 0) * s,
		p + Vector3(0, 0, 1) * s, p + Vector3(1, 0, 1) * s,
		p + Vector3(1, 1, 1) * s, p + Vector3(0, 1, 1) * s
	]

	var uv_rect = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	for i in range(4):
		vertices.append(v[vert_idx[i]])
		normals.append(normal)
		uvs.append(uv_rect[i])

	indices.append_array([
		base_index, base_index + 1, base_index + 2,
		base_index, base_index + 2, base_index + 3
	])

func _add_collision_box(parent: Node, grid_pos: Vector3i):
	var body = StaticBody3D.new()
	var shape = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(BLOCK_SIZE, BLOCK_SIZE, BLOCK_SIZE)
	shape.shape = box
	body.transform.origin = grid_pos * BLOCK_SIZE
	body.add_child(shape)
	parent.add_child(body)

func _get_directions():
	return [
		{ "offset": Vector3i(0, 0, -1), "normal": Vector3(0, 0, -1), "verts": [0, 1, 2, 3] },
		{ "offset": Vector3i(0, 0, 1), "normal": Vector3(0, 0, 1), "verts": [5, 4, 7, 6] },
		{ "offset": Vector3i(-1, 0, 0), "normal": Vector3(-1, 0, 0), "verts": [4, 0, 3, 7] },
		{ "offset": Vector3i(1, 0, 0), "normal": Vector3(1, 0, 0), "verts": [1, 5, 6, 2] },
		{ "offset": Vector3i(0, 1, 0), "normal": Vector3(0, 1, 0), "verts": [3, 2, 6, 7] },
		{ "offset": Vector3i(0, -1, 0), "normal": Vector3(0, -1, 0), "verts": [4, 5, 1, 0] }
	]
