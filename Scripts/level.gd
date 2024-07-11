extends Node3D

var chunk_size = Vector3(16, 16, 16)
var block_size = 2.0 # Each block is 2x2 world coordinates
var blocks = {} # A dictionary to store block types at positions

@export var texture_atlas: Texture2D
var texture_atlas_size = Vector2(48, 32) # Size of the texture atlas grid in pixels

var noise = FastNoiseLite.new()

class BlockType:
	var name: String
	var top_uv: Rect2
	var side_uv: Rect2
	var bottom_uv: Rect2

	func _init(name, top_uv, side_uv, bottom_uv):
		self.name = name
		self.top_uv = top_uv
		self.side_uv = side_uv
		self.bottom_uv = bottom_uv

func normalize_uv(rect: Rect2, atlas_size: Vector2) -> Rect2:
	return Rect2(
		rect.position / atlas_size,
		rect.size / atlas_size
	)

# Define block types with normalized UV coordinates
var BLOCK_TYPES = {
	"Grass": BlockType.new("Grass", 
		normalize_uv(Rect2(0, 0, 16, 16), texture_atlas_size),    # Top
		normalize_uv(Rect2(32, 0, 16, 16), texture_atlas_size),   # Side
		normalize_uv(Rect2(12, 0, 16, 16), texture_atlas_size)    # Bottom
	),
	#Dirt uses grass right now, just to show the texture rotation issue
	"Dirt": BlockType.new("Dirt", 
		normalize_uv(Rect2(0, 0, 16, 16), texture_atlas_size),    # Top
		normalize_uv(Rect2(32, 0, 16, 16), texture_atlas_size),   # Side
		normalize_uv(Rect2(16, 0, 16, 16), texture_atlas_size)    # Bottom
	),
	"Stone": BlockType.new("Stone", 
		normalize_uv(Rect2(0, 32, 16, 16), texture_atlas_size),
		normalize_uv(Rect2(16, 32, 16, 16), texture_atlas_size),
		normalize_uv(Rect2(32, 32, 16, 16), texture_atlas_size)
	)
}

func _ready():
	# Load the texture atlas
	texture_atlas = load("res://Textures/texture_atlas.png")
	
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
				if y == height - 1:
					blocks[Vector3(x, y, z)] = "Grass"
				elif y >= height - 3:
					blocks[Vector3(x, y, z)] = "Dirt"
				else:
					blocks[Vector3(x, y, z)] = "Stone"

func generate_chunk_mesh():
	var mesh = ArrayMesh.new()
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	
	var vertices = PackedVector3Array()
	var normals = PackedVector3Array()
	var uvs = PackedVector2Array()
	var indices = PackedInt32Array()

	for pos in blocks.keys():
		if is_surface_block(pos):
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
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		material.albedo_texture = texture_atlas
		mesh_instance.material_override = material
		
		add_child(mesh_instance)
		
		# Add collision shapes for each block
		for block_pos in blocks.keys():
			add_block_collision(block_pos)
		
		print("Mesh generated with vertices: ", vertices.size(), " and indices: ", indices.size())

func add_block_faces(vertices, normals, uvs, indices, position, block_type):
	var base_index = vertices.size()
	var scale = block_size  # Scale each block to be 2 units in size

	var block_data = BLOCK_TYPES[block_type]
	
	var faces = [
		# Top face
		[Vector3(0, 1, 0), [Vector3(0, 1, 0) * scale, Vector3(1, 1, 0) * scale, Vector3(1, 1, 1) * scale, Vector3(0, 1, 1) * scale], block_data.top_uv],
		# Bottom face
		[Vector3(0, -1, 0), [Vector3(0, 0, 0) * scale, Vector3(0, 0, 1) * scale, Vector3(1, 0, 1) * scale, Vector3(1, 0, 0) * scale], block_data.bottom_uv],
		# Right face
		[Vector3(1, 0, 0), [Vector3(1, 0, 0) * scale, Vector3(1, 0, 1) * scale, Vector3(1, 1, 1) * scale, Vector3(1, 1, 0) * scale], block_data.side_uv],
		# Left face
		[Vector3(-1, 0, 0), [Vector3(0, 0, 0) * scale, Vector3(0, 1, 0) * scale, Vector3(0, 1, 1) * scale, Vector3(0, 0, 1) * scale], block_data.side_uv],
		# Front face
		[Vector3(0, 0, 1), [Vector3(0, 0, 1) * scale, Vector3(0, 1, 1) * scale, Vector3(1, 1, 1) * scale, Vector3(1, 0, 1) * scale], block_data.side_uv],
		# Back face
		[Vector3(0, 0, -1), [Vector3(0, 0, 0) * scale, Vector3(1, 0, 0) * scale, Vector3(1, 1, 0) * scale, Vector3(0, 1, 0) * scale], block_data.side_uv]
	]

	for face in faces:
		var normal = face[0]
		var face_vertices = face[1]
		var uv_rect = face[2]
		var uv_coords = [
			uv_rect.position,
			uv_rect.position + Vector2(uv_rect.size.x, 0),
			uv_rect.position + uv_rect.size,
			uv_rect.position + Vector2(0, uv_rect.size.y)
		]

		# Add vertices and normals
		for vertex in face_vertices:
			vertices.append((position * block_size) + vertex)  # Adjust position with block size
			normals.append(normal)

		# Ensure the UV coordinates are correctly applied in the right order
		if normal == Vector3(0, 1, 0):
			# Top face (no rotation needed)
			uvs.append(uv_coords[0])
			uvs.append(uv_coords[1])
			uvs.append(uv_coords[2])
			uvs.append(uv_coords[3])
			
		elif normal == Vector3(0, -1, 0):
			# Bottom face (rotate 180 degrees)
			uvs.append(uv_coords[2])
			uvs.append(uv_coords[3])
			uvs.append(uv_coords[0])
			uvs.append(uv_coords[1])
		
		#Think faces are wrong. Comeback to. 
		elif normal == Vector3(1, 0, 0):
			# Right face (rotate 90 degrees clockwise)
			uvs.append(uv_coords[2])
			uvs.append(uv_coords[3])
			uvs.append(uv_coords[0])
			uvs.append(uv_coords[1])
		
		#This one faces inwards - COMPLETE
		elif normal == Vector3(-1, 0, 0):
			# Left face (rotate 90 degrees counter-clockwise)
			uvs.append(uv_coords[3])
			uvs.append(uv_coords[0])
			uvs.append(uv_coords[1])
			uvs.append(uv_coords[2])
		
		# Front (+Z) - COMPLETE
		elif normal == Vector3(0, 0, 1):
			# Front face (no rotation needed) (3,0,1,2)
			uvs.append(uv_coords[3])
			uvs.append(uv_coords[0])
			uvs.append(uv_coords[1])
			uvs.append(uv_coords[2])
			
		# Back (-Z) Not inwards side of map
		elif normal == Vector3(0, 0, -1):
			# Back face (rotate 180 degrees)
			uvs.append(uv_coords[3])
			uvs.append(uv_coords[2])
			uvs.append(uv_coords[1])
			uvs.append(uv_coords[0])

		# Ensure the winding order of the indices is consistent
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

func update_chunk_mesh():
	# Clear previous children to remove old mesh and collision shapes
	print("Clearing old mesh and collision shapes...")
	for child in get_children():
		if child is MeshInstance3D or child is StaticBody3D:
			child.queue_free()

	print("Old children cleared. Regenerating chunk mesh...")
	generate_chunk_mesh()

	# Verify camera and lighting
	var camera = get_node("/root/Level/Player/Camera3D")
	if camera:
		print("Camera found: ", camera.name, " Position: ", camera.global_transform.origin)
	else:
		print("Error: Camera not found!")

	var light = get_node("/root/Level/DirectionalLight3D")
	if light:
		print("Light found: ", light.name, " Position: ", light.global_transform.origin)
	else:
		print("Error: Light not found!")
	


func destroy_block(world_coordinate):
	var position = (world_coordinate / block_size).floor()
	print("Destroying block at grid position: ", position)
	if blocks.has(position):
		blocks.erase(position)
		update_chunk_mesh()
	else:
		print("Error: No block found at ", position)

func place_block(world_coordinate, block_type):
	var position = (world_coordinate / block_size).floor()
	print("Placing block at grid position: ", position, " with type: ", block_type)
	blocks[position] = block_type
	update_chunk_mesh()
