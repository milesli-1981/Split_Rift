extends CharacterBody2D
# 移除 class_name BasePlayer，改用路径继承以避免符号冲突

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
enum ChargeState { NONE, CHARGING, HOLDING, RELEASING }
var charge_state: ChargeState = ChargeState.NONE
var charge_time: float = 0.0
var charge_threshold: float = 0.6
var is_charging: bool = false # Keep for compatibility if needed, but we'll use charge_state
var initial_modulate: Color

var character_data: Dictionary = {}

# Rapid fire variables
var fire_timer: float = 0.0
var fire_rate: float = 0.1

# Energy / Boss mechanics
var energy: float = 0.0
var max_energy: float = 30.0
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
var anim_speed: float = 0.15
var custom_anim_sequence: Array = [0, 1, 2, 3]
var frame_offsets: Array = []
var base_sprite_offset: Vector2 = Vector2.ZERO
var base_sprite_scale: Vector2 = Vector2(1.0, 1.0)

var auto_shoot_enabled: bool = true
var charge_release_cooldown: float = 0.0

var charge_effect_timer: float = 0.0
var charge_effect_frame: int = 0

@onready var animated_sprite = get_node_or_null("Body")
@onready var charge_vfx = get_node_or_null("chargeEffect")

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
		modulate = Color(1, 1, 0)
		modulate.a = 0.6 if player_id == 2 else 1.0
		if Input.is_action_just_pressed(input_prefix + "fire") or \
		   Input.is_action_just_pressed(input_prefix + "left") or \
		   Input.is_action_just_pressed(input_prefix + "right"):
			stun_time -= 0.1
		return

	_handle_movement(delta)
	handle_shooting(delta)

func _handle_movement(delta):
	var direction = Vector2.ZERO
	if is_ai:
		direction = _get_ai_direction(delta)
	else:
		direction = Input.get_vector(input_prefix + "left", input_prefix + "right", input_prefix + "up", input_prefix + "down")
	
	velocity = direction * speed
	move_and_slide()
	
	position.x = clamp(position.x, min_x + 40, max_x - 40)
	position.y = clamp(position.y, camera_y - (camera_y * 0.8), camera_y + (camera_y * 0.8))

func _init_visual_nodes():
	# 检查是否使用了自定义场景
	var has_custom_scene = character_data.has("character_scene_path") and character_data["character_scene_path"] != ""
	
	if has_custom_scene:
		var ext_sf = _get_sprite_frames_from_data()
		if ext_sf:
			if animated_sprite:
				animated_sprite.sprite_frames = ext_sf
	else:
		_load_sprite_frames_from_data()

	if animated_sprite:
		if animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation("idle"):
			animated_sprite.animation = "idle"
			animated_sprite.play("idle")
		
		if has_custom_scene:
			base_sprite_scale = animated_sprite.scale
			base_sprite_offset = animated_sprite.offset
		else:
			var s_scale = character_data.get("sprite_scale", Vector2(1.0, 1.0))
			animated_sprite.scale = s_scale
			base_sprite_scale = s_scale
			base_sprite_offset = character_data.get("sprite_offset", Vector2.ZERO)
			
		frame_offsets = character_data.get("frame_offsets", [])
		animated_sprite.visible = true
	
		if not animated_sprite.frame_changed.is_connected(_on_animated_sprite_frame_changed):
			animated_sprite.frame_changed.connect(_on_animated_sprite_frame_changed)
			
	_init_charge_vfx_node()
	
	if charge_vfx and charge_vfx is AnimatedSprite2D:
		if not charge_vfx.animation_finished.is_connected(_on_charge_vfx_finished):
			charge_vfx.animation_finished.connect(_on_charge_vfx_finished)

func _get_sprite_frames_from_data() -> SpriteFrames:
	var path = character_data.get("sprite_frames_path", "")
	if path != "" and ResourceLoader.exists(path):
		return load(path)
	return null

func _load_sprite_frames_from_data():
	var sf = _get_sprite_frames_from_data()
	
	if not sf and character_data.has("idle_sprite_path"):
		var idle_tex = load(character_data["idle_sprite_path"])
		if idle_tex:
			sf = SpriteFrames.new()
			sf.add_animation("idle")
			sf.add_frame("idle", idle_tex)

	if sf and animated_sprite:
		animated_sprite.sprite_frames = sf

func _init_charge_vfx_node():
	var config = character_data.get("charge_visuals", {})
	var vfx = charge_vfx
	
	if vfx:
		vfx.visible = false
		if not config.is_empty():
			var tex_path = config.get("sprite_path", "")
			if tex_path != "" and ResourceLoader.exists(tex_path):
				var tex = load(tex_path)
				if vfx is Sprite2D:
					vfx.texture = tex
					vfx.hframes = config.get("hframes", 1)
					vfx.vframes = config.get("vframes", 1)
				elif vfx is AnimatedSprite2D:
					var has_custom_scene = character_data.has("character_scene_path") and character_data["character_scene_path"] != ""
					if not has_custom_scene or vfx.sprite_frames == null:
						var sf = SpriteFrames.new()
						sf.add_animation("default")
						sf.set_animation_loop("default", true)
						var h = config.get("hframes", 1)
						var v = config.get("vframes", 1)
						if h > 1 or v > 1:
							var frame_w = tex.get_width() / h
							var frame_h = tex.get_height() / v
							for row in range(v):
								for col in range(h):
									var atlas = AtlasTexture.new()
									atlas.atlas = tex
									atlas.region = Rect2(col * frame_w, row * frame_h, frame_w, frame_h)
									sf.add_frame("default", atlas)
						else:
							sf.add_frame("default", tex)
						vfx.sprite_frames = sf
			
			if vfx is AnimatedSprite2D:
				vfx.stop()

func _set_charge_state(new_state: ChargeState):
	if charge_state == new_state: return
	charge_state = new_state
	is_charging = (charge_state != ChargeState.NONE)
	
	match charge_state:
		ChargeState.NONE:
			_on_charge_state_none()
		ChargeState.CHARGING:
			_on_charge_state_charging()
		ChargeState.HOLDING:
			_on_charge_state_holding()
		ChargeState.RELEASING:
			_on_charge_state_releasing()

func _on_charge_state_none():
	charge_time = 0.0
	if charge_vfx:
		charge_vfx.visible = false
	_play_body_anim("idle")

func _on_charge_state_charging():
	charge_time = 0.0
	if charge_vfx:
		charge_vfx.visible = true
		if charge_vfx is AnimatedSprite2D and charge_vfx.sprite_frames and charge_vfx.sprite_frames.has_animation("charging"):
			charge_vfx.play("charging")
	_play_body_anim("charging")

func _on_charge_state_holding():
	if charge_vfx:
		if charge_vfx is AnimatedSprite2D and charge_vfx.sprite_frames and charge_vfx.sprite_frames.has_animation("holding"):
			charge_vfx.play("holding")
	_play_body_anim("holding")

func _on_charge_state_releasing():
	var has_releasing_anim = false
	if charge_vfx:
		if charge_vfx is AnimatedSprite2D and charge_vfx.sprite_frames and charge_vfx.sprite_frames.has_animation("releasing"):
			charge_vfx.play("releasing")
			has_releasing_anim = true
	
	_play_body_anim("releasing")
	
	var lv = int(charge_time / charge_threshold)
	if lv >= 1:
		_execute_charge_shoot(lv)
		if lv >= 2:
			_send_opponent_attacks() 
			if lv >= 3:
				_summon_boss()
				energy = 0.0
			else:
				_send_charge_fireballs()
				energy -= 20.0
		
		var config = character_data.get("charge_visuals", {})
		charge_release_cooldown = config.get("release_cooldown", 0.5)
		_emit_energy_signal()
		
		# 如果没有释放动画，直接回到 NONE
		if not has_releasing_anim:
			_set_charge_state(ChargeState.NONE)
	else:
		_set_charge_state(ChargeState.NONE)

func _play_body_anim(anim_name: String):
	if not animated_sprite: return
	if animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation(anim_name):
		if animated_sprite.animation != anim_name:
			animated_sprite.play(anim_name)
	else:
		if animated_sprite.animation != "idle":
			animated_sprite.play("idle")

func _on_charge_vfx_finished():
	if charge_state == ChargeState.RELEASING:
		_set_charge_state(ChargeState.NONE)
	elif not is_charging and charge_vfx:
		charge_vfx.visible = false

func _update_visuals(delta):
	_update_charge_visuals(delta)

func _on_animated_sprite_frame_changed():
	if not animated_sprite: return
	var current_anim = animated_sprite.animation
	var current_frame = animated_sprite.frame
	var offset = base_sprite_offset
	
	if current_anim == "idle":
		if frame_offsets.size() > current_frame:
			offset += frame_offsets[current_frame]
	elif current_anim == "charge":
		var charge_config = character_data.get("charge_visuals", {})
		var c_offsets = charge_config.get("frame_offsets", [])
		if c_offsets.size() > current_frame:
			offset += c_offsets[current_frame]
	
	animated_sprite.offset = offset

# VIRTUAL: Override in subclasses for specific VFX
func _update_charge_visuals(delta):
	var config = character_data.get("charge_visuals", {})
	if config.is_empty(): return
	var vfx = charge_vfx
	if not vfx: return

	# 根据状态更新 VFX
	match charge_state:
		ChargeState.CHARGING:
			if vfx is AnimatedSprite2D and vfx.sprite_frames and vfx.sprite_frames.has_animation("charging"):
				pass
			else:
				_manual_vfx_charge(vfx, delta)
		ChargeState.HOLDING:
			# Holding 状态通常是循环动画，由 _on_charge_state_holding 启动
			pass
		ChargeState.RELEASING:
			if vfx is AnimatedSprite2D and vfx.sprite_frames and vfx.sprite_frames.has_animation("releasing"):
				pass
			else:
				_manual_vfx_release(vfx, config, delta)

func _manual_vfx_charge(vfx, _delta):
	var total_frames = 16
	if vfx is Sprite2D: total_frames = vfx.hframes * vfx.vframes
	elif vfx is AnimatedSprite2D: total_frames = vfx.sprite_frames.get_frame_count("default")
	var progress = clamp(charge_time / charge_threshold, 0.0, 1.0)
	var buildup_frames = total_frames / 2
	vfx.frame = int(progress * (buildup_frames - 1))

func _manual_vfx_release(vfx, config, delta):
	var total_frames = 16
	if vfx is Sprite2D: total_frames = vfx.hframes * vfx.vframes
	elif vfx is AnimatedSprite2D: total_frames = vfx.sprite_frames.get_frame_count("default")
	charge_effect_timer += delta
	var frame_speed = config.get("release_anim_speed", 0.05)
	if charge_effect_timer >= frame_speed:
		charge_effect_timer = 0.0
		charge_effect_frame += 1
		if charge_effect_frame >= total_frames:
			vfx.visible = false
			charge_effect_frame = 0
		else:
			vfx.frame = charge_effect_frame

func _reset_visuals():
	if animated_sprite:
		if animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation("idle"):
			animated_sprite.animation = "idle"
		animated_sprite.play()
		animated_sprite.scale = base_sprite_scale
		animated_sprite.modulate = Color.WHITE
	_set_charge_state(ChargeState.NONE)
	charge_changed.emit(0, 0.0, 1)

func handle_shooting(delta):
	if fire_timer > 0: fire_timer -= delta
	if charge_release_cooldown > 0:
		charge_release_cooldown -= delta
		if charge_release_cooldown <= 0: charge_time = 0.0
	_handle_bomb()
	var fire_pressed = Input.is_action_pressed(input_prefix + "fire")
	var should_fire = (auto_shoot_enabled and not fire_pressed) or is_ai
	if not is_instance_valid(active_laser) and not is_charging:
		if should_fire:
			while fire_timer <= 0:
				_execute_normal_shoot()
				fire_timer += fire_rate
	else:
		if is_charging or fire_pressed:
			fire_timer = fire_rate
	_handle_charge_input(delta)

# VIRTUAL: Override in subclasses for specific normal attack
func _execute_normal_shoot():
	if bullet_scene:
		var bullet = bullet_scene.instantiate()
		bullet.global_position = global_position + Vector2(0, -20)
		bullet.player_id = player_id
		bullet.damage = 1
		bullet.bullet_index = character_data.get("bullet_index", 0)
		get_parent().add_child(bullet)

func _handle_charge_input(delta):
	if is_ai:
		_handle_ai_charge(delta)
		return

	var fire_pressed = Input.is_action_pressed(input_prefix + "fire")
	var fire_just_released = Input.is_action_just_released(input_prefix + "fire")
	
	if charge_release_cooldown > 0:
		return

	match charge_state:
		ChargeState.NONE:
			if fire_pressed:
				if is_instance_valid(active_laser):
					active_laser.queue_free() # Or some other cleanup
				_set_charge_state(ChargeState.CHARGING)
		
		ChargeState.CHARGING:
			if fire_pressed:
				charge_time += delta
				var max_unlocked_lv = max(1, int(energy / 10.0))
				var max_charge_time = max_unlocked_lv * charge_threshold
				
				# 发送进度信号
				var ratio = clamp(charge_time / max_charge_time, 0.0, 1.0)
				var lv = int(charge_time / charge_threshold)
				charge_changed.emit(lv, ratio, max_unlocked_lv)
				
				if charge_time >= max_charge_time:
					_set_charge_state(ChargeState.HOLDING)
			elif fire_just_released:
				_set_charge_state(ChargeState.RELEASING)
			else:
				_set_charge_state(ChargeState.NONE)
				
		ChargeState.HOLDING:
			if not fire_pressed or fire_just_released:
				_set_charge_state(ChargeState.RELEASING)
			else:
				# 保持满额信号
				var max_unlocked_lv = max(1, int(energy / 10.0))
				charge_changed.emit(max_unlocked_lv, 1.0, max_unlocked_lv)
				
		ChargeState.RELEASING:
			# 释放状态主要由动画结束触发回到 NONE
			pass

var ai_charge_timer: float = 0.0
var ai_is_holding_charge: bool = false
var ai_target_charge_lv: int = 1

func _handle_ai_charge(delta):
	if not ai_is_holding_charge:
		if energy >= 10.0 and randf() < 0.005:
			ai_is_holding_charge = true
			ai_target_charge_lv = randi_range(1, int(energy / 10.0))
			ai_charge_timer = 0.0
			_set_charge_state(ChargeState.CHARGING)
	
	if ai_is_holding_charge:
		ai_charge_timer += delta
		charge_time = ai_charge_timer # 同步蓄力时间用于视觉显示
		
		if charge_state == ChargeState.CHARGING and ai_charge_timer >= ai_target_charge_lv * charge_threshold:
			_set_charge_state(ChargeState.HOLDING)
			
		if ai_charge_timer >= ai_target_charge_lv * charge_threshold + 0.3:
			ai_is_holding_charge = false
			_set_charge_state(ChargeState.RELEASING)

func _release_charge_attack(lv):
	# 这个函数现在主要由 _on_charge_state_releasing 内部逻辑替代
	# 为了兼容性保留但逻辑转移
	pass

# VIRTUAL: Override in subclasses for specific charge attack
func _execute_charge_shoot(level: int):
	var main = get_tree().root.find_child("Main", true, false)
	if main and main.has_method("spawn_charge_attack"):
		var charge_type = character_data.get("charge_type", "WAVE")
		_spawn_charge_wave(main, charge_type)
		get_tree().create_timer(0.3).timeout.connect(func(): 
			if is_inside_tree():
				_spawn_charge_wave(main, charge_type)
		)

func _spawn_charge_wave(main, charge_type):
	var pos_bottom = global_position + Vector2(0, 100)
	main.spawn_charge_attack(player_id, charge_type, pos_bottom, self)
	var pos_left = global_position + Vector2(-100, 0)
	main.spawn_charge_attack(player_id, charge_type, pos_left, self)
	var pos_right = global_position + Vector2(100, 0)
	var ex = main.spawn_charge_attack(player_id, charge_type, pos_right, self)
	if charge_type == "LASER" and ex:
		active_laser = ex

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

func use_bomb():
	invincibility_time = 3.0
	var world = get_tree().root.find_child("World", true, false)
	if world:
		for enemy in get_tree().get_nodes_in_group("enemies"):
			if (player_id == 1 and enemy.position.x < 800) or (player_id == 2 and enemy.position.x > 800):
				enemy.take_damage(10, player_id)
		for fireball in get_tree().get_nodes_in_group("fireballs"):
			if (player_id == 1 and fireball.position.x < 800) or (player_id == 2 and fireball.position.x > 800):
				fireball.queue_free()

func take_damage(amount: int):
	if CharacterManager.debug_mode: return
	if invincibility_time > 0: return
	health -= amount
	health_changed.emit(health)
	if health > 0:
		stun_time = 1.5
		invincibility_time = 2.5
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
	visible = false
	set_physics_process(false)
	set_process(false)
	position = Vector2(-10000, -10000)

func gain_energy(amount: float):
	energy = min(energy + amount, max_energy)
	_emit_energy_signal()

func _emit_energy_signal():
	var lv = int(energy / 10.0)
	var pct = (fmod(energy, 10.0) / 10.0) if lv < 3 else 1.0
	energy_changed.emit(lv, pct)

func _get_ai_direction(_delta) -> Vector2:
	var target_x = global_position.x
	var target_y = global_position.y
	var threats = []
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if (player_id == 1 and enemy.global_position.x < 800) or (player_id == 2 and enemy.global_position.x > 800):
			threats.append(enemy)
	for fireball in get_tree().get_nodes_in_group("fireballs"):
		if fireball.target_player_id == player_id:
			threats.append(fireball)
	if threats.size() > 0:
		threats.sort_custom(func(a, b): return global_position.distance_to(a.global_position) < global_position.distance_to(b.global_position))
		var primary = threats[0]
		target_x = primary.global_position.x
		if global_position.distance_to(primary.global_position) < 150:
			if primary is Area2D and primary.is_in_group("fireballs"):
				target_x = primary.global_position.x
			else:
				if global_position.x < primary.global_position.x: target_x = primary.global_position.x - 100
				else: target_x = primary.global_position.x + 100
	else:
		target_x = 400 if player_id == 1 else 1200
		target_y = camera_y + 200
	var dir = Vector2(target_x - global_position.x, target_y - global_position.y)
	if dir.length() > 10: return dir.normalized()
	return Vector2.ZERO

func _send_charge_fireballs():
	var main = get_tree().root.find_child("Main", true, false)
	if main:
		var target_id = 2 if player_id == 1 else 1
		for i in range(2):
			var spawn_pos = global_position + Vector2(randf_range(-200, 200), -400)
			main.send_fireball(target_id, 0, 0, spawn_pos)

func _send_opponent_attacks():
	var main = get_tree().root.find_child("Main", true, false)
	if main and main.has_method("send_opponent_attack"):
		var target_id = 2 if player_id == 1 else 1
		var extra_type = character_data.get("extra_type", "WAVE")
		var count = 2 if extra_type != "SWARM" else 5
		for i in range(count):
			var spawn_pos = global_position + Vector2(randf_range(-100, 100), -20)
			main.send_opponent_attack(target_id, extra_type, spawn_pos, self)

func _summon_boss():
	var world_node = get_tree().root.find_child("World", true, false)
	if world_node:
		for fireball in get_tree().get_nodes_in_group("fireballs"):
			if "fireball_type" in fireball and fireball.fireball_type == 3:
				if (player_id == 1 and fireball.position.x < 800) or (player_id == 2 and fireball.position.x > 800):
					fireball.queue_free()
	var main = get_tree().root.find_child("Main", true, false)
	if main:
		var target_id = 2 if player_id == 1 else 1
		main.send_fireball(target_id, 0, 3, global_position)
