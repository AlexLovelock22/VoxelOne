extends Node3D

@export var CHUNK_SIZE: int = 16
@export var BLOCK_SIZE: float = 1.0
@export var CHUNK_HEIGHT: int = 128

var chunk_manager 
var noise: FastNoiseLite
var chunk_offset: Vector3i
var block_map: Dictionary = {}
var mesh_generated := false

func set_chunk_data(p_noise: FastNoiseLite, p_offset: Vector3i):
	noise = p_noise
	chunk_offset = p_offset

func _ready():
	generate_chunk()  # Still needed to populate block_map

func generate_chunk():
	_generate_block_map()
	# DO NOT call _generate_visible_mesh() here — it will be triggered later by chunk_manager


func generate_mesh():
	#print("Meshing chunk at ", chunk_offset)
	_generate_visible_mesh()

func _generate_block_map():
	if noise == null:
		push_error("Noise generator not set before block map generation!")
		return

	for x in range(CHUNK_SIZE):
		for z in range(CHUNK_SIZE):
			var world_x = chunk_offset.x + x
			var world_z = chunk_offset.z + z

			# Get the raw noise value and calculate height
			var raw_height = noise.get_noise_2d(world_x, world_z)
			var height = clamp(roundi(raw_height * (CHUNK_SIZE / 2.0) + (CHUNK_SIZE / 2.0)), 0, CHUNK_SIZE)

			# Log column height calculation
			#print("🌍 Column (%d, %d) raw: %.6f → rounded height: %d" % [world_x, world_z, raw_height, height])

			for y in range(height):
				var block_pos = Vector3i(x, y, z)
				block_map[block_pos] = true


	
func _is_inside_chunk(pos: Vector3i) -> bool:
	return pos.x >= 0 and pos.x < CHUNK_SIZE \
		and pos.y >= 0 and pos.y < CHUNK_SIZE \
		and pos.z >= 0 and pos.z < CHUNK_SIZE

func is_ready() -> bool:
	return mesh_generated

func _generate_visible_mesh():
	# Clean up old mesh + collisions
	if $MeshInstance3D.mesh:
		$MeshInstance3D.mesh.clear_surfaces()

	for child in get_children():
		if child is StaticBody3D:
			remove_child(child)
			child.queue_free()

	var mesh = ArrayMesh.new()
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)

	var vertices = PackedVector3Array()
	var normals = PackedVector3Array()
	var uvs = PackedVector2Array()
	var indices = PackedInt32Array()
	var index_offset = 0
	
	# --- TOP FACES (y+)
	for y in range(CHUNK_SIZE):
		var visited := {}
		for z in range(CHUNK_SIZE):
			for x in range(CHUNK_SIZE):
				var pos = Vector3i(x, y, z)
				if visited.has(pos) or not block_map.has(pos):
					continue

				var adjacent := Vector3i(x, y + 1, z)
				var occluded := false

				if _is_inside_chunk(adjacent):
					occluded = block_map.has(adjacent)
				else:
					var world_adj = Vector3(chunk_offset) + Vector3(adjacent) * BLOCK_SIZE
					occluded = chunk_manager.is_block_solid_at_world_pos(world_adj)

				if occluded:
					continue

				var width := 1
				while x + width < CHUNK_SIZE:
					var p2 = Vector3i(x + width, y, z)
					var a2 = Vector3i(x + width, y + 1, z)

					var occluded2 := false
					if _is_inside_chunk(a2):
						occluded2 = block_map.has(a2)
					else:
						var world_a2 = Vector3(chunk_offset) + Vector3(a2) * BLOCK_SIZE
						occluded2 = chunk_manager.is_block_solid_at_world_pos(world_a2)

					if block_map.has(p2) and not occluded2 and not visited.has(p2):
						width += 1
					else:
						break

				var height := 1
				while z + height < CHUNK_SIZE:
					var can_extend := true
					for dx in range(width):
						var cp = Vector3i(x + dx, y, z + height)
						var ca = Vector3i(x + dx, y + 1, z + height)

						var occluded3 := false
						if _is_inside_chunk(ca):
							occluded3 = block_map.has(ca)
						else:
							var world_ca = Vector3(chunk_offset) + Vector3(ca) * BLOCK_SIZE
							occluded3 = chunk_manager.is_block_solid_at_world_pos(world_ca)

						if not block_map.has(cp) or occluded3 or visited.has(cp):
							can_extend = false
							break
					if can_extend:
						height += 1
					else:
						break

				for dz in range(height):
					for dx in range(width):
						visited[Vector3i(x + dx, y, z + dz)] = true

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
					uvs.append(Vector2(v.x, v.z) * 0.1)

				indices.append_array([
					index_offset, index_offset + 1, index_offset + 2,
					index_offset, index_offset + 2, index_offset + 3
				])
				index_offset += 4


		# --- BOTTOM FACES (y−)
	for y in range(CHUNK_SIZE):
		var visited := {}
		for z in range(CHUNK_SIZE):
			for x in range(CHUNK_SIZE):
				var pos = Vector3i(x, y, z)
				if visited.has(pos) or not block_map.has(pos):
					continue

				var adjacent := Vector3i(x, y - 1, z)
				var occluded := false

				if _is_inside_chunk(adjacent):
					occluded = block_map.has(adjacent)
				else:
					var world_adj = Vector3(chunk_offset) + Vector3(adjacent) * BLOCK_SIZE
					occluded = chunk_manager.is_block_solid_at_world_pos(world_adj)

				if occluded:
					continue

				var width := 1
				while x + width < CHUNK_SIZE:
					var p2 = Vector3i(x + width, y, z)
					var b2 = Vector3i(x + width, y - 1, z)

					var occluded2 := false
					if _is_inside_chunk(b2):
						occluded2 = block_map.has(b2)
					else:
						var world_b2 = Vector3(chunk_offset) + Vector3(b2) * BLOCK_SIZE
						occluded2 = chunk_manager.is_block_solid_at_world_pos(world_b2)

					if block_map.has(p2) and not occluded2 and not visited.has(p2):
						width += 1
					else:
						break

				var height := 1
				while z + height < CHUNK_SIZE:
					var can_extend := true
					for dx in range(width):
						var cp = Vector3i(x + dx, y, z + height)
						var cb = Vector3i(x + dx, y - 1, z + height)

						var occluded3 := false
						if _is_inside_chunk(cb):
							occluded3 = block_map.has(cb)
						else:
							var world_cb = Vector3(chunk_offset) + Vector3(cb) * BLOCK_SIZE
							occluded3 = chunk_manager.is_block_solid_at_world_pos(world_cb)

						if not block_map.has(cp) or occluded3 or visited.has(cp):
							can_extend = false
							break
					if can_extend:
						height += 1
					else:
						break

				for dz in range(height):
					for dx in range(width):
						visited[Vector3i(x + dx, y, z + dz)] = true

				var p = Vector3(x, y, z) * BLOCK_SIZE
				var w = width * BLOCK_SIZE
				var h = height * BLOCK_SIZE
				var face_vertices = [
					p,
					p + Vector3(0, 0, h),
					p + Vector3(w, 0, h),
					p + Vector3(w, 0, 0)
				]

				for v in face_vertices:
					vertices.append(v)
					normals.append(Vector3.DOWN)
					uvs.append(Vector2(v.x, v.z) * 0.1)

				indices.append_array([
					index_offset, index_offset + 1, index_offset + 2,
					index_offset, index_offset + 2, index_offset + 3
				])
				index_offset += 4


	# --- RIGHT FACES (x+)
	for x in range(CHUNK_SIZE):
		var visited := {}
		for y in range(CHUNK_SIZE):
			for z in range(CHUNK_SIZE):
				var pos = Vector3i(x, y, z)
				if visited.has(pos) or not block_map.has(pos):
					continue

				var adjacent := Vector3i(x + 1, y, z)
				var occluded := false

				if _is_inside_chunk(adjacent):
					occluded = block_map.has(adjacent)
				else:
					var world_adj = Vector3(chunk_offset) + Vector3(adjacent) * BLOCK_SIZE
					occluded = chunk_manager.is_block_solid_at_world_pos(world_adj)

				if occluded:
					continue

				var width = 1
				while z + width < CHUNK_SIZE:
					var next = Vector3i(x, y, z + width)
					var next_adj = Vector3i(x + 1, y, z + width)

					var occluded2 := false
					if _is_inside_chunk(next_adj):
						occluded2 = block_map.has(next_adj)
					else:
						var world_next = Vector3(chunk_offset) + Vector3(next_adj) * BLOCK_SIZE
						occluded2 = chunk_manager.is_block_solid_at_world_pos(world_next)

					if block_map.has(next) and not occluded2 and not visited.has(next):
						width += 1
					else:
						break

				var height = 1
				while y + height < CHUNK_SIZE:
					var can_extend := true
					for dz in range(width):
						var cp = Vector3i(x, y + height, z + dz)
						var ca = Vector3i(x + 1, y + height, z + dz)

						var occluded3 := false
						if _is_inside_chunk(ca):
							occluded3 = block_map.has(ca)
						else:
							var world_check = Vector3(chunk_offset) + Vector3(ca) * BLOCK_SIZE
							occluded3 = chunk_manager.is_block_solid_at_world_pos(world_check)

						if not block_map.has(cp) or occluded3 or visited.has(cp):
							can_extend = false
							break

					if can_extend:
						height += 1
					else:
						break

				for dz in range(width):
					for dy in range(height):
						visited[Vector3i(x, y + dy, z + dz)] = true

				var p = Vector3(x + 1, y, z) * BLOCK_SIZE
				var w = width * BLOCK_SIZE
				var h = height * BLOCK_SIZE
				var face_vertices = [
					p,
					p + Vector3(0, 0, w),
					p + Vector3(0, h, w),
					p + Vector3(0, h, 0)
				]

				for v in face_vertices:
					vertices.append(v)
					normals.append(Vector3.RIGHT)
					uvs.append(Vector2(v.y, v.z) * 0.1)

				indices.append_array([
					index_offset, index_offset + 1, index_offset + 2,
					index_offset, index_offset + 2, index_offset + 3
				])
				index_offset += 4


		# --- LEFT FACES (x−)
	for x in range(CHUNK_SIZE):
		var visited := {}
		for y in range(CHUNK_SIZE):
			for z in range(CHUNK_SIZE):
				var pos = Vector3i(x, y, z)
				if visited.has(pos) or not block_map.has(pos):
					continue

				var adjacent := Vector3i(x - 1, y, z)
				var occluded := false

				if _is_inside_chunk(adjacent):
					occluded = block_map.has(adjacent)
				else:
					var world_adj = Vector3(chunk_offset) + Vector3(adjacent) * BLOCK_SIZE
					occluded = chunk_manager.is_block_solid_at_world_pos(world_adj)

				if occluded:
					continue

				var width = 1
				while z + width < CHUNK_SIZE:
					var next = Vector3i(x, y, z + width)
					var next_adj = Vector3i(x - 1, y, z + width)

					var occluded2 := false
					if _is_inside_chunk(next_adj):
						occluded2 = block_map.has(next_adj)
					else:
						var world_next = Vector3(chunk_offset) + Vector3(next_adj) * BLOCK_SIZE
						occluded2 = chunk_manager.is_block_solid_at_world_pos(world_next)

					if block_map.has(next) and not occluded2 and not visited.has(next):
						width += 1
					else:
						break

				var height = 1
				while y + height < CHUNK_SIZE:
					var can_extend := true
					for dz in range(width):
						var cp = Vector3i(x, y + height, z + dz)
						var ca = Vector3i(x - 1, y + height, z + dz)

						var occluded3 := false
						if _is_inside_chunk(ca):
							occluded3 = block_map.has(ca)
						else:
							var world_check = Vector3(chunk_offset) + Vector3(ca) * BLOCK_SIZE
							occluded3 = chunk_manager.is_block_solid_at_world_pos(world_check)

						if not block_map.has(cp) or occluded3 or visited.has(cp):
							can_extend = false
							break

					if can_extend:
						height += 1
					else:
						break

				for dz in range(width):
					for dy in range(height):
						visited[Vector3i(x, y + dy, z + dz)] = true

				var p = Vector3(x, y, z) * BLOCK_SIZE
				var w = width * BLOCK_SIZE
				var h = height * BLOCK_SIZE
				var face_vertices = [
					p,
					p + Vector3(0, h, 0),
					p + Vector3(0, h, w),
					p + Vector3(0, 0, w)
				]

				for v in face_vertices:
					vertices.append(v)
					normals.append(Vector3.LEFT)
					uvs.append(Vector2(v.y, v.z) * 0.1)

				indices.append_array([
					index_offset, index_offset + 1, index_offset + 2,
					index_offset, index_offset + 2, index_offset + 3
				])
				index_offset += 4

		# --- FRONT FACES (z+)
	for z in range(CHUNK_SIZE):
		var visited := {}
		for y in range(CHUNK_SIZE):
			for x in range(CHUNK_SIZE):
				var pos = Vector3i(x, y, z)
				if visited.has(pos) or not block_map.has(pos):
					continue

				var adjacent := Vector3i(x, y, z + 1)
				var occluded := false
				if _is_inside_chunk(adjacent):
					occluded = block_map.has(adjacent)
				else:
					var world_adj = Vector3(chunk_offset) + Vector3(adjacent) * BLOCK_SIZE
					occluded = chunk_manager.is_block_solid_at_world_pos(world_adj)

				if occluded:
					continue

				var width = 1
				while x + width < CHUNK_SIZE:
					var next = Vector3i(x + width, y, z)
					var next_adj = Vector3i(x + width, y, z + 1)

					var occluded2 := false
					if _is_inside_chunk(next_adj):
						occluded2 = block_map.has(next_adj)
					else:
						var world_next = Vector3(chunk_offset) + Vector3(next_adj) * BLOCK_SIZE
						occluded2 = chunk_manager.is_block_solid_at_world_pos(world_next)

					if block_map.has(next) and not occluded2 and not visited.has(next):
						width += 1
					else:
						break

				var height = 1
				while y + height < CHUNK_SIZE:
					var can_extend := true
					for dx in range(width):
						var cp = Vector3i(x + dx, y + height, z)
						var ca = Vector3i(x + dx, y + height, z + 1)

						var occluded3 := false
						if _is_inside_chunk(ca):
							occluded3 = block_map.has(ca)
						else:
							var world_check = Vector3(chunk_offset) + Vector3(ca) * BLOCK_SIZE
							occluded3 = chunk_manager.is_block_solid_at_world_pos(world_check)

						if not block_map.has(cp) or occluded3 or visited.has(cp):
							can_extend = false
							break

					if can_extend:
						height += 1
					else:
						break

				for dx in range(width):
					for dy in range(height):
						visited[Vector3i(x + dx, y + dy, z)] = true

				var p = Vector3(x, y, z + 1) * BLOCK_SIZE
				var w = width * BLOCK_SIZE
				var h = height * BLOCK_SIZE
				var face_vertices = [
					p,
					p + Vector3(0, h, 0),
					p + Vector3(w, h, 0),
					p + Vector3(w, 0, 0)
				]

				for v in face_vertices:
					vertices.append(v)
					normals.append(Vector3.FORWARD)
					uvs.append(Vector2(v.x, v.y) * 0.1)

				indices.append_array([
					index_offset, index_offset + 1, index_offset + 2,
					index_offset, index_offset + 2, index_offset + 3
				])
				index_offset += 4
				
				
					# --- BACK FACES (z−)
	for z in range(CHUNK_SIZE):
		var visited := {}
		for y in range(CHUNK_SIZE):
			for x in range(CHUNK_SIZE):
				var pos = Vector3i(x, y, z)
				if visited.has(pos) or not block_map.has(pos):
					continue

				var adjacent := Vector3i(x, y, z - 1)
				var occluded := false
				if _is_inside_chunk(adjacent):
					occluded = block_map.has(adjacent)
				else:
					var world_adj = Vector3(chunk_offset) + Vector3(adjacent) * BLOCK_SIZE
					occluded = chunk_manager.is_block_solid_at_world_pos(world_adj)

				if occluded:
					continue

				var width = 1
				while x + width < CHUNK_SIZE:
					var next = Vector3i(x + width, y, z)
					var next_adj = Vector3i(x + width, y, z - 1)

					var occluded2 := false
					if _is_inside_chunk(next_adj):
						occluded2 = block_map.has(next_adj)
					else:
						var world_next = Vector3(chunk_offset) + Vector3(next_adj) * BLOCK_SIZE
						occluded2 = chunk_manager.is_block_solid_at_world_pos(world_next)

					if block_map.has(next) and not occluded2 and not visited.has(next):
						width += 1
					else:
						break

				var height = 1
				while y + height < CHUNK_SIZE:
					var can_extend := true
					for dx in range(width):
						var cp = Vector3i(x + dx, y + height, z)
						var ca = Vector3i(x + dx, y + height, z - 1)

						var occluded3 := false
						if _is_inside_chunk(ca):
							occluded3 = block_map.has(ca)
						else:
							var world_check = Vector3(chunk_offset) + Vector3(ca) * BLOCK_SIZE
							occluded3 = chunk_manager.is_block_solid_at_world_pos(world_check)

						if not block_map.has(cp) or occluded3 or visited.has(cp):
							can_extend = false
							break

					if can_extend:
						height += 1
					else:
						break

				for dx in range(width):
					for dy in range(height):
						visited[Vector3i(x + dx, y + dy, z)] = true

				var p = Vector3(x, y, z) * BLOCK_SIZE
				var w = width * BLOCK_SIZE
				var h = height * BLOCK_SIZE
				var face_vertices = [
					p,
					p + Vector3(w, 0, 0),
					p + Vector3(w, h, 0),
					p + Vector3(0, h, 0)
				]

				for v in face_vertices:
					vertices.append(v)
					normals.append(Vector3.BACK)
					uvs.append(Vector2(v.x, v.y) * 0.1)

				indices.append_array([
					index_offset, index_offset + 1, index_offset + 2,
					index_offset, index_offset + 2, index_offset + 3
				])
				index_offset += 4


	# TODO: Add LEFT, FORWARD, and BACK face passes similarly
	
	# Finalize mesh
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
	
	mesh_generated = true
	#print("✅ Chunk mesh updated with %d vertices, %d indices" % [vertices.size(), indices.size()])



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
	

func set_block_at_local_pos(local_pos: Vector3i, is_solid: bool):
	if is_solid:
		block_map[local_pos] = true
	else:
		block_map.erase(local_pos)

	generate_mesh()

