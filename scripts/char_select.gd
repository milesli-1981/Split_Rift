extends Control

@onready var char_list = $Panel/VBoxContainer/CharList
@onready var desc_label = $Panel/VBoxContainer/DescLabel
@onready var p2_status = $Panel/VBoxContainer/P2Status
@onready var debug_label = $Panel/VBoxContainer/DebugModeLabel

var selected_index = 0
var char_keys = []

func _ready():
	char_keys = CharacterManager.CHARACTERS.keys()
	_update_ui()

func _input(event):
	if event.is_action_pressed("p1_up"):
		selected_index = posmod(selected_index - 1, char_keys.size())
		_update_ui()
	elif event.is_action_pressed("p1_down"):
		selected_index = posmod(selected_index + 1, char_keys.size())
		_update_ui()
	elif event.is_action_pressed("p1_fire"):
		_confirm_selection()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_X:
		CharacterManager.debug_mode = !CharacterManager.debug_mode
		_update_ui()

func _update_ui():
	if debug_label:
		debug_label.text = "Debug Mode (X): " + ("ON" if CharacterManager.debug_mode else "OFF")
		debug_label.modulate = Color.GREEN if CharacterManager.debug_mode else Color.YELLOW

	var key = char_keys[selected_index]
	var data = CharacterManager.CHARACTERS[key]

	desc_label.text = "[ " + data["display_name"] + " ]\n"
	desc_label.text += "速度: " + _get_stars(data["speed"], 300, 600) + "  "
	desc_label.text += "射速 " + _get_stars(1.0/data["fire_rate"], 4, 13) + "  "
	desc_label.text += "蓄力: " + _get_stars(2.0 - data["charge_speed"], 0.4, 1.3) + "\n"
	desc_label.text += "蓄力类型: " + data["charge_desc"]

	# Visual highlight in list (simplified)
	for i in range(char_list.get_child_count()):
		var label = char_list.get_child(i)
		label.modulate = Color.YELLOW if i == selected_index else Color.WHITE

func _get_stars(val, min_v, max_v):
	var ratio = clamp((val - min_v) / (max_v - min_v), 0, 1)
	var count = int(ratio * 5) + 1
	var stars = ""
	for i in range(count):
		stars += "★"
	return stars

func _confirm_selection():
	CharacterManager.p1_choice = char_keys[selected_index]

	# AI random choice for P2
	var p2_idx = randi() % char_keys.size()
	CharacterManager.p2_choice = char_keys[p2_idx]

	p2_status.text = "P2 (AI) 已选择: " + CharacterManager.CHARACTERS[CharacterManager.p2_choice]["display_name"]

	# Start game after short delay
	await get_tree().create_timer(1.0).timeout
	get_tree().change_scene_to_file("res://scenes/Main.tscn")
