extends Control

@onready var char_list = $Panel/VBoxContainer/CharList
@onready var desc_label = $Panel/VBoxContainer/DescLabel
@onready var p2_status = $Panel/VBoxContainer/P2Status
@onready var debug_label = $Panel/VBoxContainer/DebugModeLabel

var selected_index = 0
var char_keys = []
var portrait_preview: TextureRect

func _ready():
	print("CharSelect: Initializing...")
	
	char_keys = CharacterManager.CHARACTERS.keys()
	_setup_portrait_preview()
	_setup_char_list()
	_update_ui()
	print("CharSelect: Initialization complete. Keys: ", char_keys)

func _process(_delta):
	# 使用 InputMap 动作处理输入
	if Input.is_action_just_pressed("p1_up"):
		_handle_nav(-1)
	elif Input.is_action_just_pressed("p1_down"):
		_handle_nav(1)
	elif Input.is_action_just_pressed("p1_fire"):
		_confirm_selection()

func _input(event):
	# 允许 X 键切换调试模式
	if event is InputEventKey and event.pressed and event.keycode == KEY_X:
		CharacterManager.debug_mode = !CharacterManager.debug_mode
		_update_ui()

func _handle_nav(dir):
	if char_keys.size() > 0:
		selected_index = (selected_index + dir + char_keys.size()) % char_keys.size()
		print("CharSelect: Navigating to index ", selected_index)
		_update_ui()

func _setup_portrait_preview():
	# Create a portrait preview if it doesn't exist
	portrait_preview = TextureRect.new()
	portrait_preview.custom_minimum_size = Vector2(120, 120)
	portrait_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# Add it above the description label
	var index = desc_label.get_index()
	desc_label.get_parent().add_child(portrait_preview)
	desc_label.get_parent().move_child(portrait_preview, index)

func _setup_char_list():
	print("CharSelect: Setting up char list...")
	if not char_list:
		print("CharSelect: ERROR - char_list is NULL")
		return
	
	# Clear existing static labels
	for child in char_list.get_children():
		char_list.remove_child(child)
		child.queue_free()
	
	print("CharSelect: Creating labels for keys: ", char_keys)
	# Create dynamic labels for each character
	for key in char_keys:
		var data = CharacterManager.CHARACTERS[key]
		var label = Label.new()
		label.text = data.get("display_name", key)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		char_list.add_child(label)
	print("CharSelect: Char list setup complete.")

func _update_ui():
	print("CharSelect: Updating UI for index: ", selected_index)
	if debug_label:
		debug_label.text = "Debug Mode (X): " + ("ON" if CharacterManager.debug_mode else "OFF")
		debug_label.modulate = Color.GREEN if CharacterManager.debug_mode else Color.YELLOW

	if char_keys.size() == 0: 
		print("CharSelect: No characters found!")
		return
		
	var key = char_keys[selected_index]
	var data = CharacterManager.CHARACTERS[key]
	print("CharSelect: Selected character: ", key)

	desc_label.text = "[ " + data.get("display_name", key) + " ]\n"
	desc_label.text += "速度: " + _get_stars(data.get("speed", 400), 300, 600) + "  "
	
	var fr = data.get("fire_rate", 0.1)
	if fr == 0: fr = 0.1
	desc_label.text += "射速 " + _get_stars(1.0/fr, 4, 13) + "  "
	desc_label.text += "蓄力: " + _get_stars(2.0 - data.get("charge_speed", 1.0), 0.4, 1.3) + "\n"
	desc_label.text += "蓄力类型: " + data.get("charge_desc", "未知")

	# Update portrait preview
	if data.has("portrait_path") and ResourceLoader.exists(data["portrait_path"]):
		portrait_preview.texture = load(data["portrait_path"])
		portrait_preview.visible = true
	else:
		portrait_preview.visible = false

	# Visual highlight in list
	var children = char_list.get_children()
	for i in range(children.size()):
		var label = children[i]
		label.modulate = Color.YELLOW if i == selected_index else Color.WHITE
		# 恢复原始文本显示
		var other_key = char_keys[i]
		label.text = CharacterManager.CHARACTERS[other_key].get("display_name", other_key)

func _get_stars(val, min_v, max_v):
	var ratio = clamp((val - min_v) / (max_v - min_v), 0, 1)
	var count = int(ratio * 5) + 1
	var stars = ""
	for i in range(count):
		stars += "★"
	return stars

func _confirm_selection():
	if selected_index >= char_keys.size(): return
	
	CharacterManager.p1_choice = char_keys[selected_index]

	# AI random choice for P2
	var p2_idx = randi() % char_keys.size()
	CharacterManager.p2_choice = char_keys[p2_idx]

	p2_status.text = "P2 (AI) 已选择: " + CharacterManager.CHARACTERS[CharacterManager.p2_choice]["display_name"]

	# Start game after short delay
	await get_tree().create_timer(1.0).timeout
	get_tree().change_scene_to_file("res://scenes/Main.tscn")
