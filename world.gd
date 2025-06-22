extends Node3D

@onready var player = $Player
@onready var chunk_manager = $ChunkManager

func _ready():
	player.chunk_manager = chunk_manager
	print("✅ ChunkManager assigned to player.")
