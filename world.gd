extends Node3D

@onready var player = $Player
@onready var chunk_manager = $ChunkManager

func _ready():
	player.chunk_manager = chunk_manager
	print("✅ ChunkManager assigned to player.")

func _process(_delta):
	if Input.is_action_pressed("debug_monitor"):
		var draw_calls := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		var primitives := Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		print("🖼️ Draw Calls:", draw_calls, "| 🔺 Primitives:", primitives)

