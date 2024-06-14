extends Node3D

var chunk_size = Vector3(16, 16, 16)
var block_size = 2.0 # Each block is 2x2 world coordinates
var blocks = {} # A dictionary to store block types at positions

@export var texture_atlas: Texture2D
var texture_atlas_size = Vector2(2, 2) # Size of the texture atlas grid (2x2 in this example)

var noise = FastNoiseLite.new()

func _ready():
	# Initialize the noise parameters
	noise.seed = randi()
	noise.fractal_octaves = 4
	
	# Generate terrain using noise
	generate_terrain()

	generate_chunk_mesh()

func generate_terrain():
	for x in range(chunk_size.x):
		for z in range(chunk_size.z):
			var height = int(noise.get_noise_2d(float(x), float(z)) * (chunk_size.y / 2)) + int(chunk_size.y / 2)
			for y in range(height):
				blocks[Vector3(x, y, z)] = "Stone"  # Example block type

func generate_chunk_mesh():
	var mesh = ArrayMesh.new()
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	
	var vertices = PackedVector3Array()
	var normals = PackedVector3Array()
	var uvs = PackedVector2Array()
	var indices = PackedInt32Array()

	for x in range(chunk_size.x):
		for y in range(chunk_size.y):
			for z in range(chunk_size.z):
				var pos = Vector3(x, y, z)
				if blocks.has(pos) and is_surface_block(pos):
					add_block_faces(vertices, normals, uvs, indices, pos, blocks[pos])

	if vertices.size() == 0:
		print("No vertices were added, blocks might be missing or not on the surface.")
	else:
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_INDEX] = indices
		
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var mesh_instance = MeshInstance3D.new()
		mesh_instance.mesh = mesh
		
		# Create and assign a material with the texture atlas
		var material = StandardMaterial3D.new()
		material.albedo_texture = texture_atlas
		mesh_instance.material_override = material
		
		add_child(mesh_instance)
		
		# Add collision shapes for each block
		for block_pos in blocks.keys():
			add_block_collision(block_pos)

func add_block_faces(vertices, normals, uvs, indices, position, block_type):
	var base_index = vertices.size()
	var scale = block_size  # Scale each block to be 2 units in size

	var faces = [
		# Top face
		[Vector3(0, 1, 0), [Vector3(0, 1, 0) * scale, Vector3(1, 1, 0) * scale, Vector3(1, 1, 1) * scale, Vector3(0, 1, 1) * scale]],
		# Bottom face
		[Vector3(0, -1, 0), [Vector3(0, 0, 0) * scale, Vector3(0, 0, 1) * scale, Vector3(1, 0, 1) * scale, Vector3(1, 0, 0) * scale]],
		# Right face
		[Vector3(1, 0, 0), [Vector3(1, 0, 0) * scale, Vector3(1, 0, 1) * scale, Vector3(1, 1, 1) * scale, Vector3(1, 1, 0) * scale]],
		# Left face
		[Vector3(-1, 0, 0), [Vector3(0, 0, 0) * scale, Vector3(0, 1, 0) * scale, Vector3(0, 1, 1) * scale, Vector3(0, 0, 1) * scale]],
		# Front face
		[Vector3(0, 0, 1), [Vector3(0, 0, 1) * scale, Vector3(0, 1, 1) * scale, Vector3(1, 1, 1) * scale, Vector3(1, 0, 1) * scale]],
		# Back face
		[Vector3(0, 0, -1), [Vector3(0, 0, 0) * scale, Vector3(1, 0, 0) * scale, Vector3(1, 1, 0) * scale, Vector3(0, 1, 0) * scale]]
	]

	for face in faces:
		var normal = face[0]
		var face_vertices = face[1]

		for vertex in face_vertices:
			vertices.append((position * block_size) + vertex)  # Adjust position with block size
			normals.append(normal)
		
		var uv_start = Vector2(0, 0)
		var uv_size = Vector2(1.0 / texture_atlas_size.x, 1.0 / texture_atlas_size.y)
		var uv_coords = [
			uv_start,
			uv_start + Vector2(uv_size.x, 0),
			uv_start + uv_size,
			uv_start + Vector2(0, uv_size.y)
		]

		for uv in uv_coords:
			uvs.append(uv)
		
		indices.append(base_index)
		indices.append(base_index + 1)
		indices.append(base_index + 2)
		indices.append(base_index)
		indices.append(base_index + 2)
		indices.append(base_index + 3)

		base_index += 4

func add_block_collision(position):
	var static_body = StaticBody3D.new()
	var collision_shape = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.extents = Vector3(block_size / 2, block_size / 2, block_size / 2)
	collision_shape.shape = shape
	
	static_body.add_child(collision_shape)
	
	# Set the transform of StaticBody3D to position the collision shape
	var transform = Transform3D()
	transform.origin = position * block_size + Vector3(block_size / 2, block_size / 2, block_size / 2)
	static_body.transform = transform
	
	add_child(static_body)


func is_surface_block(pos):
	var directions = [
		Vector3(1, 0, 0), Vector3(-1, 0, 0), 
		Vector3(0, 1, 0), Vector3(0, -1, 0),
		Vector3(0, 0, 1), Vector3(0, 0, -1)
	]

	for dir in directions:
		var neighbor_pos = pos + dir
		if not blocks.has(neighbor_pos):
			return true
	return false
