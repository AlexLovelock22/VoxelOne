extends VBoxContainer


const LEVEL = preload("res://Scenes/level.tscn")


func _on_new_game_button_pressed():
	get_tree().change_scene_to_packed(LEVEL)



func _on_quit_button_pressed():
	get_tree().quit()
