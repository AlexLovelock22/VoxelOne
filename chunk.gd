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

	# Greedy meshing for top faces (y+)
	for y in range(CHUNK_SIZE):
		var visited := {}
		for z in range(CHUNK_SIZE):
			for x in range(CHUNK_SIZE):
				var pos = Vector3i(x, y, z)
				if visited.has(pos):
					continue

				if not block_map.has(pos):
					continue

				var above = Vector3i(x, y + 1, z)
				if block_map.has(above):
					continue # face is not visible

				# Greedily merge along +x
				var width = 1
				while x + width < CHUNK_SIZE:
					var next_pos = Vector3i(x + width, y, z)
					var next_above = Vector3i(x + width, y + 1, z)
					if block_map.has(next_pos) and not block_map.has(next_above) and not visited.has(next_pos):
						width += 1
					else:
						break

				# Greedily merge along +z
				var height = 1
				while z + height < CHUNK_SIZE:
					var can_extend = true
					for dx in range(width):
						var check_pos = Vector3i(x + dx, y, z + height)
						var check_above = Vector3i(x + dx, y + 1, z + height)
						if not block_map.has(check_pos) or block_map.has(check_above) or visited.has(check_pos):
							can_extend = false
							break
					if can_extend:
						height += 1
					else:
						break

				# Mark all merged positions as visited
				for dz in range(height):
					for dx in range(width):
						visited[Vector3i(x + dx, y, z + dz)] = true

				# Add the merged top face
				var p = Vector3(x, y + 1, z) * BLOCK_SIZE
				var w = width * BLOCK_SIZE
				var h = height * BLOCK_SIZE

				var face_vertices = [
					p,
					p + Vector3(w, 0, 0),
					p + Vector3(w, 0, h),
					p + Vector3(0, 0, h)
				]

				for v in face_vertices:
					vertices.append(v)
					normals.append(Vector3.UP)
					uvs.append(Vector2(v.x, v.z) * 0.1) # simple UVs

				indices.append_array([
					index_offset, index_offset + 1, index_offset + 2,
					index_offset, index_offset + 2, index_offset + 3
				])
				index_offset += 4

	# TODO: add non-top exposed faces here (same as current _add_face calls)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	$MeshInstance3D.mesh = mesh

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
