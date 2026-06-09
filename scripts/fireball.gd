extends Area2D

enum FireballType { NORMAL, REVERSE, EXTRA, BOSS }

@export var speed: float = 400.0
@export var health: int = 3
@export var fireball_type: FireballType = FireballType.NORMAL
@export var level: int = 1 # 鐏悆绛夌骇锛岄殢鍙嶅脊澧炲姞

var target_player_id: int = 1
var sender_player_id: int = 1
var direction: Vector2 = Vector2.DOWN
var is_reflected: bool = false
var source_combo_count: int = 0

# Parabolic movement
var is_parabolic: bool = false
var start_point: Vector2
var target_point: Vector2
var peak_height: float
var launch_time: float = 0.0
var launch_duration: float = 1.0

func _ready():
	add_to_group("fireballs")
	update_visuals()

func update_visuals():
	# 绉婚櫎鎵€鏈?modulate 棰滆壊鐗规晥浠ｇ爜锛岀伀鐞冪幇鍦ㄤ娇鐢ㄥ師濮嬪姩鐢婚鑹?
	var anim = get_node_or_null("AnimatedSprite2D")
	if anim:
		if anim.sprite_frames and anim.sprite_frames.has_animation("default"):
			anim.sprite_frames.set_animation_loop("default", true)
		anim.play("default")
	
	var shadow = get_node_or_null("Shadow")
	if shadow:
		shadow.visible = true

	# 鍒濆澶у皬涓嶇缉鏀?(Level 1 = 1.0)锛屼箣鍚庢瘡绾у鍔?15%
	var level_scale = 1.0 + (level - 1) * 0.15
	scale = Vector2.ONE * level_scale

	health = 3 # 3 hits to reflect as requested
	match fireball_type:
		FireballType.REVERSE:
			speed *= 1.3 # Faster

func launch_parabolic(start: Vector2, target: Vector2, height: float, duration: float):
	start_point = start
	target_point = target
	peak_height = height
	launch_duration = duration
	launch_time = 0.0
	is_parabolic = true

func _process(delta):
	if is_parabolic:
		launch_time += delta
		var t = launch_time / launch_duration

		if t >= 1.0:
			is_parabolic = false
			direction = Vector2.DOWN
			global_position = target_point
			# 涓嬭惤闃舵鏈濆悜姝ｄ笅鏂?
			rotation = direction.angle()
			return

		var current_x = lerp(start_point.x, target_point.x, t)
		var current_y = lerp(start_point.y, target_point.y, t) - peak_height * 4.0 * t * (1.0 - t)
		global_position = Vector2(current_x, current_y)

		var next_t = (launch_time + 0.01) / launch_duration
		var next_x = lerp(start_point.x, target_point.x, next_t)
		var next_y = lerp(start_point.y, target_point.y, next_t) - peak_height * 4.0 * next_t * (1.0 - next_t)
		# 鎶涚墿绾块樁娈靛疄鏃惰皟鏁存湞鍚戯紙鐏悆榛樿鍚戝彸锛岀洿鎺ヤ娇鐢ㄤ綅绉昏搴︼級
		rotation = (Vector2(next_x, next_y) - global_position).angle()

	elif fireball_type == FireballType.EXTRA:
		# Tracking
		_track_player(delta)
		rotation = direction.angle()
	else:
		position += direction * speed * delta
		# 鏅€氶琛岄樁娈垫湞鍚戠Щ鍔ㄦ柟鍚?
		rotation = direction.angle()

	# Cleanup off screen and handle split-screen boundaries
	_check_boundaries()

func _check_boundaries():
	var divider_x = 800.0
	# 如果是发给 P1 (左屏)
	if target_player_id == 1:
		if global_position.x > divider_x - 10 or global_position.x < -100:
			queue_free()
	# 如果是发给 P2 (右屏)
	else:
		if global_position.x < divider_x + 10 or global_position.x > 1700:
			queue_free()

	var world = get_tree().root.find_child("World", true, false)
	if world and "camera_y" in world:
		if position.y > world.camera_y + 800 or position.y < world.camera_y - 800:
			queue_free()

func _track_player(delta):
	var main = get_tree().root.find_child("Main", true, false)
	if main:
		var target = main.get_player(target_player_id)
		if target and target.visible:
			# Extra behaviors based on character's extra_type
			var extra_type = "TRACK"
			if "character_data" in target and target.character_data.has("extra_type"):
				# Note: In TSS, attack behavior is determined by the SENDER's character
				# We need to get the sender's data
				var sender = main.get_player(sender_player_id)
				if sender and "character_data" in sender:
					extra_type = sender.character_data["extra_type"]

			match extra_type:
				"MINE": # Ran's Bunny Mine: Moves slow then stays
					var target_dir = (target.global_position - global_position).normalized()
					direction = direction.lerp(target_dir, 0.5 * delta).normalized()
					position += direction * (speed * 0.5) * delta
				"SHIP": # Arthur's Ship: Moves very slow but big
					position += direction * (speed * 0.3) * delta
				"AIM": # Sprite's Aim: High speed direct aim
					var target_dir = (target.global_position - global_position).normalized()
					direction = target_dir
					position += direction * (speed * 1.5) * delta
				"SPACE": # Nanja's Space: Moves and takes space
					position += direction * speed * delta
				"TRACK": # YanYang's Track: Unstable tracking
					var target_dir = (target.global_position - global_position).normalized()
					direction = direction.lerp(target_dir, 2.0 * delta).normalized()
					position += direction * speed * delta

func take_damage(amount, source_player_id: int, _combo: int = 0):
	if fireball_type == FireballType.EXTRA:
		return # Unbreakable

	if source_player_id == target_player_id:
		health -= amount
		if health <= 0:
			if fireball_type == FireballType.BOSS:
				queue_free()
			else:
				reflect()
	else:
		health -= amount
		if health <= 0:
			queue_free()

func reflect():
	var main = get_tree().root.find_child("Main", true, false)
	if not main: return

	var player = main.get_player(target_player_id)
	if player and player.has_method("notify_reflection"):
		player.notify_reflection(fireball_type)

	if fireball_type == FireballType.NORMAL:
		fireball_type = FireballType.REVERSE
		level += 1 # 鍙嶅脊鏃跺鍔犵瓑绾?
		# Swap roles
		sender_player_id = target_player_id
		target_player_id = 1 if sender_player_id == 2 else 2
		is_reflected = true
		update_visuals()

		var world = get_tree().root.find_child("World", true, false)
		if world:
			var target_x_center = 400.0 if target_player_id == 1 else 1200.0
			var target_pos = Vector2(target_x_center + randf_range(-150, 150), world.camera_y - 300)
			launch_parabolic(global_position, target_pos, 400.0, 1.0)
	elif fireball_type == FireballType.REVERSE:
		# TSS Logic: Hitting a REVERSE fireball sends an Extra Attack to opponent
		var extra_type = "TRACK"
		if player and "character_data" in player:
			extra_type = player.character_data.get("extra_type", "TRACK")

		# Current target becomes the sender
		var sender_id = target_player_id
		var new_target_id = 1 if sender_id == 2 else 2
		main.send_opponent_attack(new_target_id, extra_type, global_position, player)
		queue_free() # The original fireball is replaced by the EX attack

func _on_body_entered(body):
	if body.is_in_group("players"):
		if body.player_id == target_player_id:
			if body.has_method("take_damage"):
				body.take_damage(3) # Damage 3 as per design doc
			queue_free()
