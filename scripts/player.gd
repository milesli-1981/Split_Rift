extends CharacterBody2D

@export var player_id: int = 1
@export var speed: float = 400.0
@export var health: int = 5
@export var bullet_scene: PackedScene
@export var is_ai: bool = false # AI control mode

signal health_changed(new_health: int)
signal energy_changed(level: int, percent: float)
signal charge_changed(level: int, percent: float, max_lv: int)
signal bombs_changed(count: int)

@export var min_x: float = 0.0
@export var max_x: float = 720.0
var scroll_speed: float = 0.0
var camera_y: float = 400.0

var input_prefix: String = "p1_"

# Charge attack variables
var charge_time: float = 0.0
var charge_threshold: float = 0.6 # Reduced from 1.0 to 0.6 for faster charging
var is_charging: bool = false # 默认不蓄力，需玩家操作
var initial_modulate: Color

var character_data: Dictionary = {}

# Rapid fire variables
var fire_timer: float = 0.0
var fire_rate: float = 0.1 # Faster fire rate (0.1s)

# Energy / Boss mechanics
var energy: float = 0.0
var max_energy: float = 30.0 # 10 per level (3 levels max)
var stun_time: float = 0.0
var bombs: int = 2
var invincibility_time: float = 0.0
var fever_time: float = 0.0
var reflected_counter_fireballs: int = 0
var reflection_timer: float = 0.0
var active_laser: Node2D = null

# Animation variables
var anim_timer: float = 0.0
var anim_frame_index: int = 0
var anim_speed: float = 0.15 # Time per frame
var custom_anim_sequence: Array = [0, 1, 2, 3] # Default sequence
var frame_offsets: Array = []
var base_sprite_offset: Vector2 = Vector2.ZERO
var base_sprite_scale: Vector2 = Vector2(1.0, 1.0)

var auto_shoot_enabled: bool = true # 恢复自动射击模式
var charge_release_cooldown: float = 0.0 # 蓄力释放后的冷却时间（动画播放时间）

var charge_effect_timer: float = 0.0
var charge_effect_frame: int = 0

@onready var animated_sprite = get_node_or_null("AnimatedSprite2D")

func is_in_fever() -> bool:
	return fever_time > 0.0

func _ready():
	input_prefix = "p1_" if player_id == 1 else "p2_"
	z_index = 10 
	
	# Load character data
	var char_key = CharacterManager.p1_choice if player_id == 1 else CharacterManager.p2_choice
	character_data = CharacterManager.CHARACTERS.get(char_key, CharacterManager.CHARACTERS["Ran"])
	
	# Apply stats from config
	speed = character_data.get("speed", 400.0)
	fire_rate = character_data.get("fire_rate", 0.1)
	charge_threshold = character_data.get("charge_speed", 0.6)
	anim_speed = character_data.get("anim_speed", 0.15)
	
	modulate = Color.WHITE
	if player_id == 2: modulate.a = 0.6 
	initial_modulate = modulate

	_init_visual_nodes()

func _physics_process(delta):
	_update_visuals(delta)
	
	# 基础颜色恢复
	modulate = initial_modulate
	
	if fever_time > 0:
		fever_time -= delta
		var fever_color = Color(0.5, 1, 1) if Engine.get_frames_drawn() % 10 < 5 else Color(1, 1, 1)
		modulate.r = fever_color.r
		modulate.g = fever_color.g
		modulate.b = fever_color.b

	if reflection_timer > 0:
		reflection_timer -= delta
		if reflection_timer <= 0: reflected_counter_fireballs = 0

	if invincibility_time > 0:
		invincibility_time -= delta
		modulate.a = (0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.05)) * (0.6 if player_id == 2 else 1.0)
	else:
		modulate.a = 0.6 if player_id == 2 else 1.0

	if stun_time > 0:
		stun_time -= delta
		modulate = Color(1, 1, 0) # 保持黄色特效
		modulate.a = 0.6 if player_id == 2 else 1.0
		if Input.is_action_just_pressed(input_prefix + "fire") or \
		   Input.is_action_just_pressed(input_prefix + "left") or \
		   Input.is_action_just_pressed(input_prefix + "right"):
			stun_time -= 0.1
		return

	_handle_movement(delta)
	handle_shooting(delta)
	
	# DEBUG
	if Input.is_key_pressed(KEY_F1) and player_id == 1: energy = max_energy; _emit_energy_signal()
	if Input.is_key_pressed(KEY_F2) and player_id == 2: energy = max_energy; _emit_energy_signal()

func _handle_movement(delta):
	var direction = Vector2.ZERO
	if is_ai:
		direction = _get_ai_direction(delta)
	else:
		direction = Input.get_vector(input_prefix + "left", input_prefix + "right", input_prefix + "up", input_prefix + "down")
	
	velocity = direction * speed
	move_and_slide()
	
	position.x = clamp(position.x, min_x + 40, max_x - 40)
	# 限制 Y 轴移动，防止进入底部 Info Panel (Dashboard) 区域
	# 现在的战斗区域高度是动态计算的，camera_y 在中心
	position.y = clamp(position.y, camera_y - (camera_y * 0.8), camera_y + (camera_y * 0.8))

func _init_visual_nodes():
	if not character_data.has("sprite_frames_path"):
		push_warning("Character data missing sprite_frames_path for: ", character_data.get("display_name", "Unknown"))
		return

	var path = character_data["sprite_frames_path"]
	var sf = load(path)
	
	if sf and sf is SpriteFrames and animated_sprite:
		animated_sprite.sprite_frames = sf
		animated_sprite.animation = "idle"
		animated_sprite.play("idle")
		animated_sprite.speed_scale = 1.0 # 确保播放速度正常
		print("Successfully loaded SpriteFrames: ", path)
	elif animated_sprite:
		# 如果加载失败，尝试播放内置动画作为回退
		if animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation("idle"):
			animated_sprite.animation = "idle"
			animated_sprite.play("idle")
			animated_sprite.speed_scale = 1.0
	
	if animated_sprite:
		# 设置基础变换
		var s_scale = character_data.get("sprite_scale", Vector2(1.0, 1.0))
		animated_sprite.scale = s_scale
		base_sprite_scale = s_scale
		base_sprite_offset = character_data.get("sprite_offset", Vector2.ZERO)
		frame_offsets = character_data.get("frame_offsets", [])
		animated_sprite.visible = true
	
		# 监听帧改变信号以应用逐帧偏移 (如果需要)
		if not animated_sprite.frame_changed.is_connected(_on_animated_sprite_frame_changed):
			animated_sprite.frame_changed.connect(_on_animated_sprite_frame_changed)
			
	# 初始化蓄力特效 (chargeEffect)
	var config = character_data.get("charge_visuals", {})
	var vfx = get_node_or_null("chargeEffect")
	if vfx and not config.is_empty():
		vfx.visible = false
		if vfx is Sprite2D:
			var tex_path = config.get("sprite_path", "")
			if tex_path != "":
				vfx.texture = load(tex_path)
				vfx.hframes = config.get("hframes", 1)
				vfx.vframes = config.get("vframes", 1)
				vfx.scale = Vector2.ONE * config.get("scale_multiplier", 1.0)

func _update_visuals(delta):
	if not animated_sprite: return

	# 始终确保播放 idle 动画，不再在蓄力时切换 body 动画
	if animated_sprite.animation != "idle":
		if animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation("idle"):
			animated_sprite.animation = "idle"
			animated_sprite.play("idle")
	elif not animated_sprite.is_playing():
		# 确保 idle 动画始终在播放
		animated_sprite.play("idle")

	_update_charge_visuals(delta)

func _on_animated_sprite_frame_changed():
	if not animated_sprite: return
	
	var current_anim = animated_sprite.animation
	var current_frame = animated_sprite.frame
	
	var offset = base_sprite_offset
	
	# 注意：这里的偏移逻辑需要根据 SpriteFrames 中的实际帧索引来微调
	if current_anim == "idle":
		if frame_offsets.size() > current_frame:
			offset += frame_offsets[current_frame]
	elif current_anim == "charge":
		var charge_config = character_data.get("charge_visuals", {})
		var c_offsets = charge_config.get("frame_offsets", [])
		if c_offsets.size() > current_frame:
			offset += c_offsets[current_frame]
	
	animated_sprite.offset = offset

func _update_charge_visuals(delta):
	var config = character_data.get("charge_visuals", {})
	if config.is_empty(): return

	# Handle Charge VFX (e.g., Taiji Circle)
	var vfx = get_node_or_null("chargeEffect")
	if not vfx: return

	var total_frames = 16 # Default to 16 if we can't determine
	if vfx is Sprite2D:
		total_frames = vfx.hframes * vfx.vframes
	elif vfx is AnimatedSprite2D:
		if vfx.sprite_frames and vfx.sprite_frames.has_animation("default"):
			total_frames = vfx.sprite_frames.get_frame_count("default")

	if not is_charging:
		# Releasing phase: play frames 8 and onwards
		if vfx.visible:
			charge_effect_timer += delta
			var frame_speed = config.get("release_anim_speed", 0.05)
			if charge_effect_timer >= frame_speed:
				charge_effect_timer = 0.0
				charge_effect_frame += 1
				if charge_effect_frame >= total_frames:
					vfx.visible = false
					vfx.rotation = 0
					charge_effect_frame = 0
				else:
					vfx.frame = charge_effect_frame
	else:
		# Charging phase: frames 0-7
		vfx.visible = config.get("vfx_enabled", true)
		if vfx is AnimatedSprite2D:
			vfx.stop() # Stop automatic playback to control frames manually
		
		var progress = clamp(charge_time / charge_threshold, 0.0, 1.0)
		var target_frame = int(progress * 7) # Frames 0-7 for charging
		vfx.frame = target_frame
		
		# Only rotate when charge is full (frame 7)
		if target_frame >= 7:
			vfx.rotation += delta * config.get("vfx_rotate_speed", 2.0)
		else:
			vfx.rotation = 0
	
	vfx.offset = Vector2.ZERO

func _reset_visuals():
	if animated_sprite:
		animated_sprite.animation = "idle"
		animated_sprite.play()
		animated_sprite.scale = base_sprite_scale
		animated_sprite.modulate = Color.WHITE
		
	var vfx = get_node_or_null("chargeEffect")
	if vfx:
		vfx.visible = false
		if vfx is AnimatedSprite2D:
			vfx.stop()
	
	# Reset status flags
	is_charging = false
	charge_time = 0.0
	charge_changed.emit(0, 0.0, 1)

func use_bomb():
	invincibility_time = 3.0
	# Clear all enemies and fireballs on my side
	var world = get_tree().root.find_child("World", true, false)
	if world:
		for enemy in get_tree().get_nodes_in_group("enemies"):
			if (player_id == 1 and enemy.position.x < 800) or (player_id == 2 and enemy.position.x > 800):
				enemy.take_damage(10, player_id) # Big damage
		for fireball in get_tree().get_nodes_in_group("fireballs"):
			if (player_id == 1 and fireball.position.x < 800) or (player_id == 2 and fireball.position.x > 800):
				fireball.queue_free()

func _get_ai_direction(_delta) -> Vector2:
	var target_x = global_position.x
	var target_y = global_position.y
	
	# Find nearest threat or enemy in my lane
	var threats = []
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if (player_id == 1 and enemy.global_position.x < 800) or (player_id == 2 and enemy.global_position.x > 800):
			threats.append(enemy)
	for fireball in get_tree().get_nodes_in_group("fireballs"):
		if fireball.target_player_id == player_id:
			threats.append(fireball)
	
	if threats.size() > 0:
		# Sort by proximity
		threats.sort_custom(func(a, b): return global_position.distance_to(a.global_position) < global_position.distance_to(b.global_position))
		var primary = threats[0]
		target_x = primary.global_position.x
		
		# If too close, try to stay at a safe distance horizontally but aligned vertically
		if global_position.distance_to(primary.global_position) < 150:
			# If it's a fireball, we WANT to hit it if we are shooting, but stay safe if not
			if primary is Area2D and primary.is_in_group("fireballs"):
				target_x = primary.global_position.x
			else:
				# Avoid collision
				if global_position.x < primary.global_position.x:
					target_x = primary.global_position.x - 100
				else:
					target_x = primary.global_position.x + 100
	else:
		# Idle: move towards center of my lane
		target_x = 400 if player_id == 1 else 1200
		target_y = camera_y + 200 # Stay at bottom
	
	var dir = Vector2(target_x - global_position.x, target_y - global_position.y)
	if dir.length() > 10:
		return dir.normalized()
	return Vector2.ZERO

func handle_shooting(delta):
	if fire_timer > 0: fire_timer -= delta
	
	if charge_release_cooldown > 0:
		charge_release_cooldown -= delta
		if charge_release_cooldown <= 0: charge_time = 0.0

	_handle_bomb()

	# 1. Normal Fire (灏婇噸 auto_shoot_enabled 鍜?is_charging)
	var fire_pressed = Input.is_action_pressed(input_prefix + "fire")
	# 濡傛灉寮€鍚簡鑷姩灏勫嚮锛屽垯鍦ㄦ湭鎸変綇蓄力閿椂灏勫嚮锛汚I 妯″紡涓嬪缁堝皾璇曞皠鍑?
	var should_fire = (auto_shoot_enabled and not fire_pressed) or is_ai
	
	if not is_instance_valid(active_laser) and not is_charging:
		if should_fire:
			while fire_timer <= 0:
				shoot()
				fire_timer += fire_rate
	else:
		# 濡傛灉姝ｅ湪蓄力锛堝寘鎷垰鎸変笅鐨?0.1s 鍒ゅ畾鍐咃級鎴栬€呮縺鍏夋縺娲伙紝閲嶇疆灏勫嚮鍐峰嵈
		if is_charging or fire_pressed:
			fire_timer = fire_rate
	
	# 2. Manual Charge Logic
	_handle_charge_input(delta)

func _handle_bomb():
	var bomb_pressed = false
	if is_ai:
		if health <= 1 and bombs > 0 and randf() < 0.01: bomb_pressed = true
	else:
		bomb_pressed = Input.is_action_just_pressed(input_prefix + "bomb")

	if bomb_pressed and bombs > 0:
		bombs -= 1
		bombs_changed.emit(bombs)
		use_bomb()

var ai_charge_timer: float = 0.0
var ai_is_holding_charge: bool = false
var ai_target_charge_lv: int = 1

func _handle_charge_input(delta):
	var fire_pressed = false
	var fire_just_released = false
	
	if is_ai:
		# AI 蓄力閫昏緫
		if not ai_is_holding_charge:
			# 濡傛灉鑳介噺瓒冲涓旈殢鏈鸿Е鍙?
			if energy >= 10.0 and randf() < 0.005:
				ai_is_holding_charge = true
				ai_target_charge_lv = randi_range(1, int(energy / 10.0))
				ai_charge_timer = 0.0
		
		if ai_is_holding_charge:
			fire_pressed = true
			ai_charge_timer += delta
			# 濡傛灉杈惧埌鐩爣绛夌骇锛岄噴鏀?
			if ai_charge_timer >= ai_target_charge_lv * charge_threshold + 0.2:
				ai_is_holding_charge = false
				fire_pressed = false
				fire_just_released = true
	else:
		fire_pressed = Input.is_action_pressed(input_prefix + "fire")
		fire_just_released = Input.is_action_just_released(input_prefix + "fire")
	
	if charge_release_cooldown > 0:
		is_charging = false
		return

	if fire_pressed:
		if is_instance_valid(active_laser):
			_reset_visuals()
		else:
			charge_time += delta
			# 鍙湁褰撴寜浣忔椂闂磋秴杩囦竴瀹氶槇鍊硷紙渚嬪 0.1s锛夋墠杩涘叆蓄力鐘舵€侊紝浠庤€屽仠姝㈡櫘閫氬皠鍑?
			if charge_time > 0.1:
				is_charging = true
			
			var max_unlocked_lv = max(1, int(energy / 10.0))
			var max_charge_time = max_unlocked_lv * charge_threshold
			charge_time = min(charge_time, max_charge_time)
			
			var ratio = charge_time / max_charge_time
			var lv = int(charge_time / charge_threshold)
			charge_changed.emit(lv, ratio, max_unlocked_lv)
	elif fire_just_released:
		var current_lv = int(charge_time / charge_threshold)
		if current_lv >= 1:
			_release_charge_attack(current_lv)
		else:
			_reset_visuals()
	else:
		if is_charging: _reset_visuals()

func _release_charge_attack(lv):
	shoot_charge(lv)
	if lv >= 2:
		_send_opponent_attacks() 
		if lv >= 3:
			_summon_boss()
			energy = 0.0
		else:
			_send_charge_fireballs()
			energy -= 20.0
	
	is_charging = false
	var config = character_data.get("charge_visuals", {})
	charge_release_cooldown = config.get("release_cooldown", 0.5)
	
	_reset_visuals()
	
	var vfx = get_node_or_null("chargeEffect")
	if vfx:
		vfx.visible = true
		charge_effect_frame = 8
		vfx.frame = 8
		if vfx is AnimatedSprite2D:
			vfx.stop()
	
	_emit_energy_signal()

func _send_charge_fireballs():
	var main = get_tree().root.find_child("Main", true, false)
	if main:
		var target_id = 2 if player_id == 1 else 1
		# Send fewer fireballs to the opponent
		for i in range(2):
			var spawn_pos = global_position + Vector2(randf_range(-200, 200), -400) # Spawn from top area of target
			main.send_fireball(target_id, 0, 0, spawn_pos) # Send normal fireballs for now, or 2 for EXTRA type

func gain_energy(amount: float):
	energy = min(energy + amount, max_energy)
	_emit_energy_signal()

func notify_reflection(type: int):
	if type == 1: # COUNTER (Reflecting a REVERSE fireball)
		reflected_counter_fireballs += 1
		reflection_timer = 1.0 # 1 second window to chain reflections
		
		if reflected_counter_fireballs == 3:
			# 3rd cumulative counter sends an Extra Attack
			_send_opponent_attacks()
		elif reflected_counter_fireballs >= 5:
			# 5th cumulative counter sends a Boss
			_summon_boss()
			reflected_counter_fireballs = 0
			reflection_timer = 0.0

func _emit_energy_signal():
	var lv = int(energy / 10.0)
	var pct = (fmod(energy, 10.0) / 10.0) if lv < 3 else 1.0
	energy_changed.emit(lv, pct)

func _summon_boss():
	# Boss Repel logic
	var world_node = get_tree().root.find_child("World", true, false)
	if world_node:
		for fireball in get_tree().get_nodes_in_group("fireballs"):
			if "fireball_type" in fireball and fireball.fireball_type == 3: # BOSS
				if (player_id == 1 and fireball.position.x < 800) or (player_id == 2 and fireball.position.x > 800):
					fireball.queue_free()
	
	var main = get_tree().root.find_child("Main", true, false)
	if main:
		var target_id = 2 if player_id == 1 else 1
		main.send_fireball(target_id, 0, 3, global_position)

func _send_opponent_attacks():
	var main = get_tree().root.find_child("Main", true, false)
	if main and main.has_method("send_opponent_attack"):
		# In TSS, Extra Attack is sent to the OPPONENT
		var target_id = 2 if player_id == 1 else 1
		# Use EXTRA_TYPE for opponent hazards
		var extra_type = character_data.get("extra_type", "WAVE")
		
		# Send to opponent's lane - reduced count to avoid spam
		var count = 2 if extra_type != "SWARM" else 5
		for i in range(count):
			var spawn_pos = global_position + Vector2(randf_range(-100, 100), -20)
			main.send_opponent_attack(target_id, extra_type, spawn_pos, self)

func shoot():
	if bullet_scene:
		var bullet = bullet_scene.instantiate()
		bullet.global_position = global_position + Vector2(0, -20)
		bullet.player_id = player_id
		bullet.damage = 1
		bullet.bullet_index = character_data.get("bullet_index", 0)
		get_parent().add_child(bullet)

func shoot_charge(level: int):
	var main = get_tree().root.find_child("Main", true, false)
	if main and main.has_method("spawn_charge_attack"):
		var charge_type = character_data.get("charge_type", "WAVE")
		
		# 绗竴娉?
		_spawn_charge_wave(main, charge_type)
		
		# 绗簩娉?(寤惰繜 0.3 绉?
		get_tree().create_timer(0.3).timeout.connect(func(): 
			if is_inside_tree():
				_spawn_charge_wave(main, charge_type)
		)

func _spawn_charge_wave(main, charge_type):
	# 1. 姝ｄ笅鏂?
	var pos_bottom = global_position + Vector2(0, 100)
	main.spawn_charge_attack(player_id, charge_type, pos_bottom, self)
	
	# 2. 宸︿晶
	var pos_left = global_position + Vector2(-100, 0)
	main.spawn_charge_attack(player_id, charge_type, pos_left, self)
	
	# 3. 鍙充晶
	var pos_right = global_position + Vector2(100, 0)
	var ex = main.spawn_charge_attack(player_id, charge_type, pos_right, self)
	
	# 濡傛灉鏄縺鍏夌被鍨嬶紝璁板綍浣滀负 active_laser
	if charge_type == "LASER" and ex:
		active_laser = ex

func take_damage(amount: int):
	if CharacterManager.debug_mode: return
	if invincibility_time > 0: return
	
	health -= amount
	health_changed.emit(health)
	
	if health > 0:
		stun_time = 1.5 # 琚嚮涓悗鍙橀粍鑹茬壒鏁堟寔缁?1.5s
		invincibility_time = 2.5 # 澧炲姞鏃犳晫鏃堕棿浠ヨ鐩栫壒鏁堟椂闂?
		if is_charging: _reset_visuals()
		
		velocity = Vector2(0, 400)
		speed *= 0.7
		fire_rate *= 1.5
		get_tree().create_timer(1.5).timeout.connect(_reset_penalties)
	else:
		die()

func _reset_penalties():
	speed = character_data.get("speed", 400.0)
	fire_rate = character_data.get("fire_rate", 0.1)

func die():
	# Hide and disable instead of queue_free to avoid null refs in Main.gd
	visible = false
	set_physics_process(false)
	set_process(false)
	# Move far away so it doesn't collide
	position = Vector2(-10000, -10000)
