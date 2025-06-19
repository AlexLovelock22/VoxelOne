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

	# Face directions
	var face_defs = [
		{ "normal": Vector3.UP,    "offset": Vector3i(0, 1, 0),  "plane": [0, 2], "y_adjust": 1.0 },
		{ "normal": Vector3.DOWN,  "offset": Vector3i(0, -1, 0), "plane": [0, 2], "y_adjust": 0.0 },
		{ "normal": Vector3.RIGHT, "offset": Vector3i(1, 0, 0),  "plane": [1, 2], "x_adjust": 1.0 },
		{ "normal": Vector3.LEFT,  "offset": Vector3i(-1, 0, 0), "plane": [1, 2], "x_adjust": 0.0 },
		{ "normal": Vector3.FORWARD, "offset": Vector3i(0, 0, 1), "plane": [0, 1], "z_adjust": 1.0 },
		{ "normal": Vector3.BACK,    "offset": Vector3i(0, 0, -1),"plane": [0, 1], "z_adjust": 0.0 },
	]

	for face in face_defs:
		var visited := {}
		var dir: Vector3i = face["offset"]
		var normal: Vector3 = face["normal"]
		var ax: int = face["plane"][0]
		var ay: int = face["plane"][1]

		for a in range(CHUNK_SIZE):
			for b in range(CHUNK_SIZE):
				for c in range(CHUNK_SIZE):
					var pos := Vector3i(0, 0, 0)
					pos[ax] = a
					pos[ay] = b
					pos[3 - ax - ay] = c

					if visited.has(pos) or not block_map.has(pos):
						continue

					var neighbor_pos = pos + dir
					if block_map.has(neighbor_pos):
						continue

					# Greedy extend width
					var width = 1
					while c + width < CHUNK_SIZE:
						var next_pos = pos
						next_pos[3 - ax - ay] = c + width
						var next_neigh = next_pos + dir
						if block_map.has(next_pos) and not block_map.has(next_neigh) and not visited.has(next_pos):
							width += 1
						else:
							break

					# Greedy extend height
					var height = 1
					while b + height < CHUNK_SIZE:
						var can_extend = true
						for w in range(width):
							var check_pos = pos
							check_pos[ay] = b + height
							check_pos[3 - ax - ay] = c + w
							var check_neigh = check_pos + dir
							if not block_map.has(check_pos) or block_map.has(check_neigh) or visited.has(check_pos):
								can_extend = false
								break
						if can_extend:
							height += 1
						else:
							break

					# Mark visited
					for h in range(height):
						for w in range(width):
							var mark = pos
							mark[ay] = b + h
							mark[3 - ax - ay] = c + w
							visited[mark] = true

					# Base position
					var base = Vector3(pos.x, pos.y, pos.z) * BLOCK_SIZE
					if dir == Vector3i(0, 1, 0): base.y += BLOCK_SIZE
					if dir == Vector3i(1, 0, 0): base.x += BLOCK_SIZE
					if dir == Vector3i(0, 0, 1): base.z += BLOCK_SIZE

					var size_a = width * BLOCK_SIZE
					var size_b = height * BLOCK_SIZE

					var dx = Vector3()
					var dy = Vector3()
					dx[ax] = size_a
					dy[ay] = size_b

					var face_vertices = [
						base,
						base + dx,
						base + dx + dy,
						base + dy
					]

					for v in face_vertices:
						vertices.append(v)
						normals.append(normal)
						uvs.append(Vector2(v.x, v.z) * 0.1)

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

	# Collision shape
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
