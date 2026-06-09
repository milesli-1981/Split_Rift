extends Area2D

enum MovementType { STRAIGHT, SINE, ZIGZAG, CIRCLE }

@export var speed: float = 120.0
@export var health: int = 5
@export var movement_type: MovementType = MovementType.STRAIGHT
@export var amplitude: float = 120.0
@export var frequency: float = 4.0
@export var explosion_scene: PackedScene = preload("res://scenes/Explosion.tscn")

var time_passed: float = 0.0
var spawn_offset: float = 0.0
var start_x: float = 0.0
var start_y: float = 0.0
var initial_camera_y: float = 0.0

# TSS Mechanics
var initial_scale: Vector2 = Vector2.ONE
var max_health: int = 5
var player_lane: int = 1 # 1 for P1's side, 2 for P2's side
var is_fever_ball: bool = false
var is_bubble: bool = false # NEW: Is wrapped in a bubble
var is_death: bool = false # NEW: Is the Grim Reaper

func _ready():
	add_to_group("enemies")
	# fever logic handled in spawn for better control

	start_x = position.x
	start_y = position.y
	initial_scale = scale
	max_health = health
	update_visuals()

	# Determine lane based on position
	player_lane = 1 if position.x < 800 else 2

func _process(delta):
	time_passed += delta

	# Only move after spawn offset delay
	if time_passed < spawn_offset:
		return

	var t = time_passed - spawn_offset

	match movement_type:
		MovementType.STRAIGHT:
			position.y += speed * delta
		MovementType.SINE:
			position.y += speed * delta
			position.x = start_x + sin(t * frequency) * amplitude
		MovementType.ZIGZAG:
			position.y += speed * delta
			# Smooth zigzag using a triangle wave
			var zigzag = abs(fmod(t * frequency, 4.0) - 2.0) - 1.0
			position.x = start_x + zigzag * amplitude
		MovementType.CIRCLE:
			# Circular motion around a moving center
			var moving_y = start_y + (t * speed)
			position.y = moving_y + sin(t * frequency) * amplitude
			position.x = start_x + cos(t * frequency) * amplitude

func update_visuals():
	if is_bubble:
		modulate = Color(0.7, 0.9, 1.0, 0.6) # Light blue transparent bubble
		scale = initial_scale * 1.3
		return

	if is_fever_ball:
		modulate = Color(0, 0.5, 1) # Keep blue
	else:
		# Red: 1, Yellow: 2, Green: 3, Blue: 4, Purple: 5
		var color = Color.WHITE
		match health:
			1: color = Color(1, 0.2, 0.2) # Red
			2: color = Color(1, 1, 0.2)   # Yellow
			3: color = Color(0.2, 1, 0.2) # Green
			4: color = Color(0.2, 0.5, 1) # Blue
			5: color = Color(0.8, 0.2, 1) # Purple
		modulate = color

	# Visual feedback: scale down based on health
	var scale_factor = 0.5 + (float(health) / 5.0) * 0.5
	scale = initial_scale * scale_factor

func take_damage(amount, source_player_id: int = 0, current_combo: int = 0):
	if is_bubble:
		is_bubble = false
		update_visuals()
		# Flash bubble pop
		var pop_tween = create_tween()
		pop_tween.tween_property(self, "modulate:a", 1.0, 0.1)
		return

	health -= amount
	update_visuals()

	# Damage flash
	var flash_tween = create_tween()
	flash_tween.tween_property(self, "modulate", Color(5.0, 5.0, 5.0), 0.05)
	flash_tween.chain().tween_callback(update_visuals)

	if health <= 0:
		# Notify player for energy gain
		var main = get_tree().root.find_child("Main", true, false)
		if main:
			var player = main.get_player(source_player_id)
			if player and player.has_method("gain_energy"):
				var gain = 2.0 # Increased from 1.0 to 2.0 for faster testing
				if player.has_method("is_in_fever") and player.is_in_fever():
					gain *= 2.0
				player.gain_energy(gain)

				if is_fever_ball:
					player.fever_time = 10.0 # 10 seconds of fever

		explode(source_player_id, current_combo + 1)
		queue_free()

func explode(source_player_id: int, combo_count: int):
	if explosion_scene:
		var explosion = explosion_scene.instantiate()
		explosion.global_position = global_position
		explosion.source_player_id = source_player_id
		explosion.combo_count = combo_count

		# Explosion size increases slightly with combo
		var power = 3.0 + min(combo_count * 0.2, 3.0)

		if combo_count > 1: # Part of a chain
			explosion.damage = 1 # Chain damage is 1

		if explosion.has_method("set"):
			explosion.explosion_scale = power

		get_parent().add_child(explosion)

		# Update HUD combo display and trigger fireballs
		var main = get_tree().root.find_child("Main", true, false)
		if main and main.has_method("update_player_combo"):
			main.update_player_combo(source_player_id, combo_count, global_position)

		queue_free()

func _on_body_entered(body):
	if body.is_in_group("players"):
		if is_death:
			var main = get_tree().root.find_child("Main", true, false)
			if main: main.trigger_game_over("DEATH")
			return

		if body.has_method("take_damage"):
			body.take_damage(1)
		queue_free()
