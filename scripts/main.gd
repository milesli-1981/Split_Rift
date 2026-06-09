extends Control

@onready var viewport1 = $MainLayout/BattleMargin/BattleArea/ViewportContainer1/Viewport1
@onready var viewport2 = $MainLayout/BattleMargin/BattleArea/ViewportContainer2/Viewport2
@onready var camera1 = $MainLayout/BattleMargin/BattleArea/ViewportContainer1/Viewport1/CameraP1
@onready var camera2 = $MainLayout/BattleMargin/BattleArea/ViewportContainer2/Viewport2/CameraP2
@onready var world = $MainLayout/BattleMargin/BattleArea/ViewportContainer1/Viewport1/World

@export var scroll_speed: float = 150.0

@onready var hud1 = $MainLayout/Dashboard/InfoArea/HUD1
@onready var hud2 = $MainLayout/Dashboard/InfoArea/HUD2
@onready var battle_area = $MainLayout/BattleMargin/BattleArea
@onready var game_over_screen = $GameOver

var p1_combo: int = 0
var p2_combo: int = 0
var p1_combo_timer: float = 0.0
var p2_combo_timer: float = 0.0
const COMBO_RESET_TIME: float = 1.5

@export var fireball_scene: PackedScene = preload("res://scenes/Fireball.tscn")
@export var extra_attack_scene: PackedScene = preload("res://scenes/ExtraAttack.tscn")
@export var charge_attack_scene: PackedScene = preload("res://scenes/ChargeAttack.tscn")
@export var void_rift_scene: PackedScene = preload("res://scenes/VoidRift.tscn")

func _ready():
	# Share the world between viewports
	viewport2.world_2d = viewport1.world_2d

	# Enable cameras
	camera1.enabled = true
	camera2.enabled = true

	# Set player boundaries and initial positions
	var p1 = world.get_node_or_null("Player1")
	var p2 = world.get_node_or_null("Player2")

	if p1:
		# Calculate viewport size based on actual container size
		# Force a slight delay to ensure UI layout is calculated
		await get_tree().process_frame
		
		var v_height = viewport1.size.y
		var v_width = viewport1.size.x
		
		# Update world's camera_y and player bounds based on actual viewport height
		world.camera_y = v_height / 2.0
		
		p1.min_x = 0.0
		p1.max_x = v_width
		p1.camera_y = world.camera_y
		p1.position = Vector2(v_width / 2.0, v_height - 150.0)
		
		# P2 lane starts at 800 in the World coordinate system
		p2.min_x = 800.0 
		p2.max_x = 800.0 + v_width
		p2.camera_y = world.camera_y
		p2.position = Vector2(800.0 + v_width / 2.0, v_height - 150.0)

		# Initial camera positions (Perfectly centered on the lanes)
		camera1.global_position = Vector2(v_width / 2.0, world.camera_y)
		camera2.global_position = Vector2(800.0 + v_width / 2.0, world.camera_y)
		
		# Update World's lane information if it has those properties
		if world.has_method("update_lane_info"):
			world.update_lane_info(v_width)

	p1.scroll_speed = scroll_speed
	p1.health_changed.connect(func(h): _on_player_health_changed(1, h))
	p1.bombs_changed.connect(func(c): hud1.update_bombs(c))
	p1.energy_changed.connect(func(lv, pct): hud1.update_energy(lv, pct))
	p1.charge_changed.connect(func(lv, pct, max_lv): hud1.update_charge(lv, pct, max_lv))
	hud1.update_health(p1.health)
	hud1.update_bombs(p1.bombs)
	hud1.update_energy(0, 0.0)
	hud1.set_portrait(p1.character_data.get("portrait_path", ""))
	hud1.set_layout_mirrored(false) # P1 portrait on left
	
	if p2:
		p2.scroll_speed = scroll_speed
		p2.is_ai = true # Set P2 to AI mode
		p2.health_changed.connect(func(h): _on_player_health_changed(2, h))
		p2.bombs_changed.connect(func(c): hud2.update_bombs(c))
		p2.energy_changed.connect(func(lv, pct): hud2.update_energy(lv, pct))
		p2.charge_changed.connect(func(lv, pct, max_lv): hud2.update_charge(lv, pct, max_lv))
		hud2.update_health(p2.health)
		hud2.update_bombs(p2.bombs)
		hud2.update_energy(0, 0.0)
		hud2.set_portrait(p2.character_data.get("portrait_path", ""))
		hud2.set_layout_mirrored(true) # P2 portrait on right

func _process(delta):
	# Update combos
	if p1_combo_timer > 0:
		p1_combo_timer -= delta
		if p1_combo_timer <= 0:
			p1_combo = 0
			hud1.update_combo(0)

	if p2_combo_timer > 0:
		p2_combo_timer -= delta
		if p2_combo_timer <= 0:
			p2_combo = 0
			hud2.update_combo(0)

func _on_player_health_changed(id, health):
	if id == 1:
		hud1.update_health(health)
	else:
		hud2.update_health(health)

	if health <= 0:
		if game_over_screen:
			trigger_game_over("PLAYER " + str(id) + " DEFEATED")
		else:
			get_tree().paused = true

func update_player_combo(player_id: int, combo_depth: int, pos: Vector2 = Vector2.ZERO):
	var effective_combo = 0
	if player_id == 1:
		p1_combo += 1
		p1_combo_timer = COMBO_RESET_TIME
		effective_combo = max(p1_combo, combo_depth)
		hud1.update_combo(effective_combo)
		_handle_combo_fireball(2, effective_combo, pos)
	elif player_id == 2:
		p2_combo += 1
		p2_combo_timer = COMBO_RESET_TIME
		effective_combo = max(p2_combo, combo_depth)
		hud2.update_combo(effective_combo)
		_handle_combo_fireball(1, effective_combo, pos)

	if effective_combo >= 2 and pos != Vector2.ZERO:
		_show_floating_combo(effective_combo, pos)

func _show_floating_combo(count: int, pos: Vector2):
	var label = Label.new()
	label.text = str(count) + " HIT!"
	label.add_theme_font_size_override("font_size", 40)
	label.modulate = Color(1, 1, 0)
	label.global_position = pos + Vector2(-50, -50)
	label.z_index = 20
	world.add_child(label)

	var tween = create_tween()
	tween.tween_property(label, "position", label.position + Vector2(0, -100), 0.5)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.5)
	tween.tween_callback(label.queue_free)

func _handle_combo_fireball(target_id: int, current_combo: int, pos: Vector2):
	# Increased threshold from 2 back to 4 to reduce fireball spam
	if current_combo >= 4 and (current_combo - 4) % 2 == 0:
		send_fireball(target_id, current_combo, -1, pos)

func trigger_game_over(reason: String = ""):
	if is_instance_valid(game_over_screen):
		game_over_screen.visible = true
		if reason != "":
			var msg_label = game_over_screen.get_node_or_null("MessageLabel")
			if msg_label: msg_label.text = reason
	get_tree().paused = true

func get_player(id: int):
	return world.get_node_or_null("Player" + str(id))

func send_fireball(target_id: int, combo: int, force_type: int = -1, source_pos: Vector2 = Vector2.ZERO):
	if not world:
		print("ERROR: World not found!")
		return

	if fireball_scene:
		var fireball = fireball_scene.instantiate()
		fireball.target_player_id = target_id
		fireball.sender_player_id = 1 if target_id == 2 else 2
		fireball.z_index = 10

		if force_type != -1:
			fireball.fireball_type = force_type
		else:
			fireball.fireball_type = 0

		fireball.update_visuals()
		world.add_child(fireball)

		if source_pos != Vector2.ZERO:
			fireball.global_position = source_pos
		else:
			var v_width = viewport1.size.x
			var target_x_center = (v_width / 2.0) if target_id == 1 else (800.0 + v_width / 2.0)
			fireball.global_position = Vector2(target_x_center, world.camera_y - 450)

		if fireball.has_method("launch_parabolic") and fireball.fireball_type != 2:
			var v_width = viewport1.size.x
			var target_x_center = (v_width / 2.0) if target_id == 1 else (800.0 + v_width / 2.0)
			var target_pos = Vector2(target_x_center + randf_range(-200, 200), world.camera_y - 300)
			var height = randf_range(300, 600)
			var duration = randf_range(1.0, 1.5)
			fireball.launch_parabolic(fireball.global_position, target_pos, height, duration)

func send_opponent_attack(target_id: int, type_str: String, source_pos: Vector2, sender_player: Node2D):
	var is_jianxiu = false
	if sender_player and sender_player.get("character_data"):
		var display_name = sender_player.character_data.get("display_name", "")
		if "剑修" in display_name:
			is_jianxiu = true
	
	if is_jianxiu and void_rift_scene:
		var rift = void_rift_scene.instantiate()
		rift.target_id = target_id
		rift.extra_type = type_str
		rift.sender_player = sender_player
		
		var v_width = viewport1.size.x
		var target_x_center = (v_width / 2.0) if target_id == 1 else (800.0 + v_width / 2.0)
		
		# Ensure spawn position is away from the player
		var spawn_pos = Vector2.ZERO
		var target_player = get_player(target_id)
		var min_dist = 220.0 # Minimum distance from player
		
		for attempt in range(10): # Try a few times to find a good spot
			var sx = target_x_center + randf_range(-v_width * 0.45, v_width * 0.45)
			var sy = world.camera_y + randf_range(100, 450)
			spawn_pos = Vector2(sx, sy)
			if target_player and is_instance_valid(target_player):
				if spawn_pos.distance_to(target_player.global_position) > min_dist:
					break
		
		rift.global_position = spawn_pos
		world.add_child(rift)
	elif extra_attack_scene:
		var ex = extra_attack_scene.instantiate()
		ex.target_player_id = target_id
		ex.sender_player_id = 1 if target_id == 2 else 2
		ex.source_player = sender_player
		
		var v_width = viewport1.size.x
		var target_x_center = (v_width / 2.0) if target_id == 1 else (800.0 + v_width / 2.0)
		
		# Ensure spawn position is away from the player
		var spawn_pos = Vector2.ZERO
		var target_player = get_player(target_id)
		var min_dist = 220.0
		
		for attempt in range(10):
			var sx = target_x_center + randf_range(-v_width * 0.45, v_width * 0.45)
			var sy = world.camera_y + randf_range(100, 450)
			spawn_pos = Vector2(sx, sy)
			if target_player and is_instance_valid(target_player):
				if spawn_pos.distance_to(target_player.global_position) > min_dist:
					break
					
		ex.global_position = spawn_pos
		world.add_child(ex)

func spawn_charge_attack(player_id: int, type_str: String, pos: Vector2, sender_player: Node2D):
	if not charge_attack_scene: return null
	
	var charge = charge_attack_scene.instantiate()
	charge.sender_player_id = player_id
	charge.source_player = sender_player
	charge.global_position = pos
	charge.z_index = 15 # 确保在玩家上方
	
	# Map string to enum
	var type_map = {
		"WAVE": 0, "LASER": 1, "MINE": 2, "SPIRAL": 3, 
		"SWARM": 4, "PIG": 5, "PLANE": 6, "RABBIT": 7, "GROW": 8
	}
	charge.type = type_map.get(type_str, 0)
	
	world.add_child(charge)
	return charge

func send_opponent_attack_direct(target_id: int, type_str: String, source_pos: Vector2, sender_player: Node2D, use_exact_pos: bool = false, initial_rotation: float = 0.0):
	if extra_attack_scene:
		var ex = extra_attack_scene.instantiate()
		ex.target_player_id = target_id
		ex.sender_player_id = sender_player.player_id
		ex.source_player = sender_player
		ex.rotation = initial_rotation
		
		# Map string to enum for ExtraAttack
		var type_map = {
			"WAVE": 0, "LASER": 1, "MINE": 2, "SPIRAL": 3, 
			"SWARM": 4, "PIG": 5, "PLANE": 6, "RABBIT": 7
		}
		ex.type = type_map.get(type_str, 0)

		if use_exact_pos:
			ex.global_position = source_pos
		else:
			var v_width = viewport1.size.x
			var target_x_center = (v_width / 2.0) if target_id == 1 else (800.0 + v_width / 2.0)
			
			# Ensure spawn position is away from the player
			var spawn_pos = Vector2.ZERO
			var target_player = get_player(target_id)
			var min_dist = 220.0
			
			for attempt in range(10):
				var sx = target_x_center + randf_range(-v_width * 0.45, v_width * 0.45)
				var sy = world.camera_y + 400
				spawn_pos = Vector2(sx, sy)
				if target_player and is_instance_valid(target_player):
					if spawn_pos.distance_to(target_player.global_position) > min_dist:
						break
			ex.global_position = spawn_pos
		
		world.add_child(ex)
