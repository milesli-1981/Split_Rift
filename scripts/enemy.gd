extends Area2D

enum MovementType { STRAIGHT, SINE, ZIGZAG, CIRCLE, RAVEN }

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

# Raven specific
var raven_state: int = 0 # 0: Dive, 1: Side-step, 2: Second Charge
var raven_target_pos: Vector2 = Vector2.ZERO
var raven_direction: Vector2 = Vector2.ZERO # Added for directional movement
var raven_sidestep_dir: float = 1.0
var raven_timer: float = 0.0
var raven_texture: Texture2D = preload("res://素材/monster/raven.png")

# TSS Mechanics
var initial_scale: Vector2 = Vector2.ONE
var max_health: int = 5
var player_lane: int = 1 # 1 for P1's side, 2 for P2's side
var is_fever_ball: bool = false
var is_bubble: bool = false # NEW: Is wrapped in a bubble
var is_death: bool = false # NEW: Is the Grim Reaper
var is_dying: bool = false # NEW: Is playing destroy animation
var death_source_player_id: int = 0
var death_current_combo: int = 0

func _ready():
	add_to_group("enemies")
	# Hide the placeholder ColorRect
	if has_node("ColorRect"):
		$ColorRect.visible = false
	
	# Start animation on 'body' node
	if has_node("body"):
		$body.play("default")
		if not $body.animation_finished.is_connected(_on_animation_finished):
			$body.animation_finished.connect(_on_animation_finished)
	# Backward compatibility for old AnimatedSprite2D node name
	elif has_node("AnimatedSprite2D"):
		$AnimatedSprite2D.play("default")
		if not $AnimatedSprite2D.animation_finished.is_connected(_on_animation_finished):
			$AnimatedSprite2D.animation_finished.connect(_on_animation_finished)

	start_x = position.x
	start_y = position.y
	initial_scale = scale * 1.5 # Overall scale increase by 50%
	max_health = health
	
	if movement_type == MovementType.RAVEN:
		# For Raven, we can either change the animation or just keep using AnimatedSprite2D
		# If you have a 'raven' animation, you could play it here:
		# if $AnimatedSprite2D.sprite_frames.has_animation("raven"):
		#     $AnimatedSprite2D.play("raven")
		
		# Set initial target and direction
		_update_raven_target()
		raven_direction = (raven_target_pos - position).normalized()
		
		# Determine sidestep direction (move towards center of lane)
		var lane_center = 400.0 if position.x < 800 else 1200.0
		raven_sidestep_dir = 1.0 if position.x < lane_center else -1.0
	
	update_visuals()

	# Determine lane based on position
	player_lane = 1 if position.x < 800 else 2

func _update_raven_target():
	var main = get_tree().root.find_child("Main", true, false)
	if main:
		var target_player = main.get_player(player_lane)
		if target_player:
			raven_target_pos = target_player.global_position
		else:
			raven_target_pos = Vector2(400 if player_lane == 1 else 1200, 700)
	else:
		raven_target_pos = Vector2(400 if player_lane == 1 else 1200, 700)

func _process(delta):
	if is_dying:
		return
		
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
		MovementType.RAVEN:
			_process_raven_movement(delta)

	_apply_separation(delta)
	_enforce_boundaries()

func _apply_separation(delta):
	# Simple separation logic to prevent enemies from overlapping
	var enemies = get_tree().get_nodes_in_group("enemies")
	var push_vector = Vector2.ZERO
	var separation_dist = 60.0 # Distance at which enemies start pushing each other
	var push_strength = 200.0 # Force of the push
	
	for other in enemies:
		if other == self or not is_instance_valid(other):
			continue
			
		# Only separate within the same lane to avoid cross-lane forces
		if other.player_lane != self.player_lane:
			continue
			
		var dist = global_position.distance_to(other.global_position)
		if dist < separation_dist and dist > 0:
			# Calculate push direction (away from other)
			var diff = global_position - other.global_position
			push_vector += diff.normalized() * (1.0 - dist / separation_dist)
			
	if push_vector != Vector2.ZERO:
		position += push_vector * push_strength * delta

func _enforce_boundaries():
	# Lane 1: 0 - 800, Lane 2: 800 - 1600
	var min_x = 0.0 if player_lane == 1 else 800.0
	var max_x = 800.0 if player_lane == 1 else 1600.0
	
	# Special handling for Raven: allow it to fly out of outer boundaries in State 2
	if movement_type == MovementType.RAVEN and raven_state >= 1:
		# Still prevent crossing the middle divider (800)
		if player_lane == 1:
			position.x = min(position.x, 800.0 - 20)
		else:
			position.x = max(position.x, 800.0 + 20)
	else:
		# Normal clamping for all other cases
		position.x = clamp(position.x, min_x + 20, max_x - 20)
	
	# Cleanup if far off screen vertically
	var main = get_tree().root.find_child("Main", true, false)
	if main and main.world:
		var cam_y = main.world.camera_y
		if position.y > cam_y + 1000 or position.y < cam_y - 1000:
			queue_free()
		
		# Extra cleanup for Raven flying off sides
		if movement_type == MovementType.RAVEN:
			if position.x < -400 or position.x > 2000:
				queue_free()

func _process_raven_movement(delta):
	var main = get_tree().root.find_child("Main", true, false)
	var cam_y = 400.0
	if main and main.world:
		cam_y = main.world.camera_y

	match raven_state:
		0: # Dive
			# Use constant direction to fly through the target point
			position += raven_direction * speed * 2.0 * delta
			
			# Check if reached lower half
			if position.y > cam_y + 100:
				raven_state = 1
				raven_timer = 0.5 # Sidestep duration
		1: # Sidestep
			raven_timer -= delta
			position.x += raven_sidestep_dir * speed * delta
			position.y += speed * 0.5 * delta # Slight downward drift
			
			if raven_timer <= 0:
				raven_state = 2
				_update_raven_target() # Update target for second charge
				raven_direction = (raven_target_pos - position).normalized()
		2: # Second Charge
			# Use constant direction to fly through the second target
			position += raven_direction * speed * 2.5 * delta
			
			# Cleanup if flies off bottom or sides after second charge
			if position.y > cam_y + 600 or position.x < -300 or position.x > 1900:
				queue_free()

func update_visuals():
	var sprite = get_node_or_null("body")
	if not sprite:
		sprite = get_node_or_null("AnimatedSprite2D")
		
	if is_dying or not sprite:
		return
	
	# Ensure default animation is playing if available
	if sprite.sprite_frames.has_animation("default"):
		if sprite.animation != "default":
			sprite.play("default")

	if is_bubble:
		sprite.modulate = Color(0.7, 0.9, 1.0, 1.0) # Light blue, but opaque
		scale = initial_scale * 1.3
		return

	if is_fever_ball:
		sprite.modulate = Color(0, 0.5, 1) # Keep blue
	else:
		# Red: 1, Yellow: 2, Green: 3, Blue: 4, Purple: 5
		# Commented out health-based coloring as requested
		# var color = Color.WHITE
		# match health:
		# 	1: color = Color(1, 0.2, 0.2) # Red
		# 	2: color = Color(1, 1, 0.2)   # Yellow
		# 	3: color = Color(0.2, 1, 0.2) # Green
		# 	4: color = Color(0.2, 0.5, 1) # Blue
		# 	5: color = Color(0.8, 0.2, 1) # Purple
		# sprite.modulate = color
		sprite.modulate = Color.WHITE

	# Visual feedback: scale down based on health
	var scale_factor = 0.5 + (float(health) / 5.0) * 0.5
	scale = initial_scale * scale_factor
	
	# Special handling for Raven if needed
	if movement_type == MovementType.RAVEN:
		# Keep initial scale
		scale = initial_scale

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
	var sprite = get_node_or_null("body")
	if not sprite: sprite = get_node_or_null("AnimatedSprite2D")
	if not sprite: sprite = self
	
	var flash_tween = create_tween()
	flash_tween.tween_property(sprite, "modulate", Color(5.0, 5.0, 5.0), 0.05)
	flash_tween.chain().tween_callback(update_visuals)

	if health <= 0:
		is_dying = true
		death_source_player_id = source_player_id
		death_current_combo = current_combo
		
		# Stop any movement and collisions
		set_physics_process(false)
		collision_layer = 0
		collision_mask = 0
		
		# Stop any active damage flashes
		var anim_sprite = get_node_or_null("body")
		if not anim_sprite: anim_sprite = get_node_or_null("AnimatedSprite2D")
		if not anim_sprite: anim_sprite = self
		
		anim_sprite.modulate = Color.WHITE
		# Keep current scale instead of resetting to initial_scale
		# scale = initial_scale 
		
		# Play destroy animation
		if anim_sprite is AnimatedSprite2D:
			var anims = anim_sprite.sprite_frames
			if anims.has_animation("destroy"):
				anim_sprite.animation = "destroy"
				anim_sprite.sprite_frames.set_animation_loop("destroy", false)
				anim_sprite.play("destroy")
			elif anims.has_animation("destory"): # Support typo
				anim_sprite.animation = "destory"
				anim_sprite.sprite_frames.set_animation_loop("destory", false)
				anim_sprite.play("destory")
			else:
				_finalize_death(source_player_id, current_combo)
		else:
			_finalize_death(source_player_id, current_combo)

func _on_animation_finished():
	if is_dying:
		var sprite = get_node_or_null("body")
		if not sprite: sprite = get_node_or_null("AnimatedSprite2D")
		if sprite:
			var anim_name = sprite.animation
			if anim_name == "destroy" or anim_name == "destory":
				_finalize_death(death_source_player_id, death_current_combo)

func _finalize_death(source_player_id: int = 0, current_combo: int = 0):
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

	# Update HUD combo display and trigger fireballs
	if main and main.has_method("update_player_combo"):
		main.update_player_combo(source_player_id, current_combo + 1, global_position)

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

func _on_body_entered(body):
	if body.is_in_group("players"):
		if is_death:
			var main = get_tree().root.find_child("Main", true, false)
			if main: main.trigger_game_over("DEATH")
			return

		if body.has_method("take_damage"):
			body.take_damage(1)
		
		# Ravens don't get destroyed on contact with player
		if movement_type != MovementType.RAVEN:
			queue_free()
