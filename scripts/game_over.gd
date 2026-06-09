extends Control

func _on_restart_button_pressed():
	get_tree().paused = false
	# Back to Character Selection instead of reloading the match
	get_tree().change_scene_to_file("res://scenes/CharSelect.tscn")
