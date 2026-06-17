extends Area2D

enum ChargePattern { WAVE, LASER, MINE, SPIRAL, SWARM, PIG, PLANE, RABBIT, GROW }

@export var type: ChargePattern = ChargePattern.WAVE
@export var sender_player_id: int = 1
@export var lifetime: float = 2.5
@export var explosion_scene: PackedScene = preload("res://scenes/Explosion.tscn")

var source_player: Node2D # Used for LASER/GROW to follow
var direction: Vector2 = Vector2.UP
var speed: float = 100.0 # 初始慢速移动
var fast_speed: float = 1200.0 # 动画结束后的快速飞行速度
var slow_speed: float = 150.0 # 动画期间的慢速移动
var is_anim_finished: bool = false
var time_passed: float = 0.0
var spawn_offset: Vector2 = Vector2.ZERO
var base_root_scale: Vector2 = Vector2.ONE
var base_sprite_scale: Vector2 = Vector2.ONE
var hits_left: int = 1 
var laser_damage_timer: float = 0.0
var laser_damage_interval: float = 0.1 
var mine_damage_timer: float = 0.0
var mine_damage_interval: float = 0.15 

@onready var polygon = get_node_or_null("Polygon2D")
@onready var animated_sprite = get_node_or_null("AnimatedSprite2D")
@onready var collision = get_node_or_null("CollisionShape2D")

func _ready():
	# Store initial scales from editor
	base_root_scale = scale
	if animated_sprite:
		base_sprite_scale = animated_sprite.scale

	# Make collision shape unique
	if collision and collision.shape:
		collision.shape = collision.shape.duplicate()

	# Charge attacks move UP by default
	direction = Vector2.UP

	# Initialization based on type
	match type:
		ChargePattern.WAVE:
			z_index = 10
		ChargePattern.SWARM:
			z_index = 10
			lifetime = 4.5
			hits_left = 3
			slow_speed = 400.0
			fast_speed = 1500.0
		ChargePattern.MINE:
			z_index = 10
			lifetime = 3.5
			slow_speed = 0.0
			fast_speed = 0.0
		ChargePattern.SPIRAL:
			z_index = 10
			lifetime = 4.0
			hits_left = 10
			slow_speed = 300.0
			fast_speed = 800.0
		ChargePattern.LASER:
			z_index = 15 # Ensure it's on top of players and enemies
		ChargePattern.GROW:
			z_index = 15
			lifetime = 2.0
			hits_left = 5
			slow_speed = 450.0
			fast_speed = 1800.0

	speed = slow_speed

	# Always connect area_entered to hit enemies/fireballs
	area_entered.connect(_on_area_entered_custom)

	# 如果有 AnimatedSprite2D，默认开始播放
	if animated_sprite:
		if animated_sprite.sprite_frames.has_animation("default"):
			animated_sprite.sprite_frames.set_animation_loop("default", false)
		
		animated_sprite.frame = 0 # 确保从第0帧开始播放，修复缺失前2帧的问题
		animated_sprite.scale = base_sprite_scale * 0.5 # 初始设置为 0.5 倍
		animated_sprite.speed_scale = 1.0 # 恢复正常动画速度
		animated_sprite.play("default")
		animated_sprite.visible = true
		# Ensure self.modulate is white so the sprite is visible
		self.modulate = Color.WHITE
		self.self_modulate = Color.WHITE

	_setup_visuals()

func _setup_visuals():
	# Ensure visibility
	visible = true
	if animated_sprite: animated_sprite.visible = true
	
	match type:
		ChargePattern.WAVE:
			if polygon:
				polygon.polygon = PackedVector2Array([Vector2(-200, 0), Vector2(200, 0), Vector2(240, -80), Vector2(-240, -80)])
				polygon.visible = true
			modulate = Color(0.4, 1.0, 1.0, 0.9)
			if collision and collision.shape is RectangleShape2D:
				collision.shape.size = Vector2(400, 80)
		ChargePattern.LASER:
			_setup_laser_visuals()
			if collision and collision.shape is RectangleShape2D:
				collision.shape.size = Vector2(50, 2000)
				collision.position.y = -1000
		ChargePattern.MINE:
			if polygon:
				polygon.polygon = _create_circle_polygon(120, 32)
				polygon.visible = true
			modulate = Color(1.0, 0.4, 0.0, 0.8)
			if collision and collision.shape:
				var circle = CircleShape2D.new()
				circle.radius = 120
				collision.shape = circle
		ChargePattern.SPIRAL:
			if polygon:
				polygon.polygon = _create_spiral_polygon(60, 24)
				polygon.visible = true
			modulate = Color(0.8, 0.2, 1.0, 0.9)
			scale = base_root_scale * 1.5
			if collision and collision.shape:
				var circle = CircleShape2D.new()
				circle.radius = 60
				collision.shape = circle
		ChargePattern.SWARM:
			if animated_sprite: animated_sprite.visible = true
			if polygon: polygon.visible = false
			scale = base_root_scale * 1.2
			modulate = Color(1.0, 1.0, 0.2)
			if collision and collision.shape is RectangleShape2D:
				collision.shape.size = Vector2(30, 30)
		ChargePattern.GROW:
			# Respect the editor's scale, but start smaller for the growth effect
			scale = base_root_scale
			_setup_grow_visuals()

func _setup_grow_visuals():
	if polygon: polygon.visible = false
	if animated_sprite:
		animated_sprite.visible = true
		animated_sprite.play("default")
		
	if collision and collision.shape is RectangleShape2D:
		collision.shape.size = Vector2(60, 20)
		collision.position.y = -10

func _setup_laser_visuals():
	if animated_sprite and animated_sprite.sprite_frames.has_animation("default"):
		if polygon: polygon.visible = false
		animated_sprite.visible = true
		animated_sprite.play("default")
		# 激光类型如果使用动画，通常需要垂直拉伸
		animated_sprite.scale.y = base_sprite_scale.y * 10.0 # 简单拉长作为激光
		animated_sprite.scale.x = base_sprite_scale.x
		# 尝试获取第一帧的高度来计算偏移
		var frame_tex = animated_sprite.sprite_frames.get_frame_texture("default", 0)
		if frame_tex:
			animated_sprite.position.y = -frame_tex.get_height() * 5.0
	elif polygon:
		polygon.polygon = PackedVector2Array([Vector2(-25, 0), Vector2(25, 0), Vector2(25, -2000), Vector2(-25, -2000)])
		polygon.visible = true
	modulate = Color(1.0, 1.0, 1.0, 0.7)

func _process(delta):
	time_passed += delta
	if time_passed >= lifetime:
		if type == ChargePattern.MINE:
			_spawn_explosion()
		queue_free()
		return

	if not is_anim_finished and animated_sprite:
		var frames = animated_sprite.sprite_frames
		if frames.has_animation("default"):
			var frame_count = frames.get_frame_count("default")
			
			# 动画期间保持 0.7 倍缩放
			if type != ChargePattern.GROW:
				animated_sprite.scale = base_sprite_scale * 0.7
			
			# 检查是否到达最后一帧
			if animated_sprite.frame >= frame_count - 1:
				if not animated_sprite.is_playing() or time_passed > 0.1:
					is_anim_finished = true
					speed = fast_speed
					animated_sprite.stop()
					animated_sprite.frame = frame_count - 1
					# 动画完成后恢复为 1.0 倍缩放 (或特定类型的特殊缩放)
					if type == ChargePattern.LASER:
						animated_sprite.scale.y = base_sprite_scale.y * 10.0
						animated_sprite.scale.x = base_sprite_scale.x
					elif type != ChargePattern.GROW:
						animated_sprite.scale = base_sprite_scale

	_update_movement(delta)
	_check_screen_boundaries()

func _check_screen_boundaries():
	var divider_x = 800.0
	# 如果是 P1 (左屏) 的攻击
	if sender_player_id == 1:
		# 越过中线进入 P2 屏幕或飞出左侧
		if global_position.x > divider_x - 10 or global_position.x < -200:
			queue_free()
	# 如果是 P2 (右屏) 的攻击
	else:
		# 越过中线进入 P1 屏幕或飞出右侧
		if global_position.x < divider_x + 10 or global_position.x > 1800:
			queue_free()

	# 通用的上下越界检查
	var main = get_tree().root.find_child("Main", true, false)
	if main:
		var world_node = main.get_node_or_null("MainLayout/BattleArea/ViewportContainer1/Viewport1/World")
		if world_node:
			var cam_y = world_node.camera_y
			if abs(global_position.y - cam_y) > 1000:
				queue_free()

func _physics_process(delta):
	if type == ChargePattern.LASER or type == ChargePattern.MINE:
		_handle_continuous_damage(delta)

func _update_movement(delta):
	time_passed += delta
	match type:
		ChargePattern.WAVE:
			position += direction * speed * delta
		ChargePattern.LASER:
			_update_laser_position()
		ChargePattern.MINE:
			_update_mine_visuals(delta)
		ChargePattern.SPIRAL:
			_update_spiral_movement(delta)
		ChargePattern.SWARM:
			_track_nearest_enemy(delta)
		ChargePattern.GROW:
			_update_grow_logic(delta)

func _update_grow_logic(delta):
	position.y -= speed * delta
	if animated_sprite and animated_sprite.visible:
		if not is_anim_finished:
			# 动画期间保持 0.7
			animated_sprite.scale = base_sprite_scale * 0.7
		else:
			# 动画完成后开始生长
			var progress = clamp(time_passed / lifetime, 0.0, 1.0)
			var growth_curve = sin(progress * PI / 2.0)
			var pulse = 1.0 + sin(time_passed * 25.0) * 0.05
			
			animated_sprite.scale.y = base_sprite_scale.y * (1.0 + (growth_curve * 1.5)) * pulse
			animated_sprite.scale.x = base_sprite_scale.x * (1.0 + (growth_curve * 0.5)) * pulse
		
		if collision and collision.shape is RectangleShape2D:
			var growth_factor = 1.0
			if is_anim_finished:
				var progress = clamp(time_passed / lifetime, 0.0, 1.0)
				growth_factor = 1.0 + sin(progress * PI / 2.0) * 2.0
			
			var current_height = 100.0 * growth_factor
			collision.shape.size = Vector2(100, current_height)
			collision.position.y = -current_height / 2.0

func _update_laser_position():
	if source_player and source_player.visible:
		# 激光跟随玩家，并保持初始的相对偏移
		global_position = source_player.global_position + spawn_offset
	else:
		queue_free()

func _update_mine_visuals(delta):
	var main = get_tree().root.find_child("Main", true, false)
	if main:
		position.y -= main.scroll_speed * delta
	scale = base_root_scale * (1.0 + 0.15 * sin(time_passed * 10.0))
	rotation += delta * 2.0

func _update_spiral_movement(delta):
	position += direction * speed * delta
	position.x += cos(time_passed * 12.0) * 400.0 * delta
	rotation += delta * 10.0

func _track_nearest_enemy(delta):
	var nearest_target = null
	var min_dist = 99999.0
	var targets = get_tree().get_nodes_in_group("enemies") + get_tree().get_nodes_in_group("fireballs")

	for target in targets:
		if (sender_player_id == 1 and target.global_position.x < 800) or (sender_player_id == 2 and target.global_position.x > 800):
			var dist = global_position.distance_to(target.global_position)
			if dist < min_dist:
				min_dist = dist
				nearest_target = target

	if nearest_target:
		var target_dir = (nearest_target.global_position - global_position).normalized()
		direction = direction.lerp(target_dir, 6.0 * delta).normalized()
		position += direction * speed * delta
	else:
		direction = direction.lerp(Vector2.UP + Vector2(sin(time_passed * 4.0), 0) * 0.5, 2.0 * delta).normalized()
		position += direction * (speed * 0.7) * delta

func _handle_continuous_damage(delta):
	if type == ChargePattern.LASER:
		_update_laser_position()
		laser_damage_timer -= delta
		if laser_damage_timer <= 0:
			laser_damage_timer = laser_damage_interval
			_apply_continuous_damage(5)
	elif type == ChargePattern.MINE:
		mine_damage_timer -= delta
		if mine_damage_timer <= 0:
			mine_damage_timer = mine_damage_interval
			_apply_continuous_damage(15)

func _apply_continuous_damage(enemy_damage: int):
	var targets = get_overlapping_areas()
	for area in targets:
		if _should_hit_area(area):
			if area.has_method("take_damage"):
				area.take_damage(enemy_damage, sender_player_id, 0)

func _should_hit_area(area: Area2D) -> bool:
	if not (area.is_in_group("enemies") or area.is_in_group("fireballs")):
		return false
	
	# 增加垂直范围检查，防止击中屏幕上方过远（未出现）或下方的目标
	var main = get_tree().root.find_child("Main", true, false)
	if main:
		var world_node = main.get_node_or_null("MainLayout/BattleArea/ViewportContainer1/Viewport1/World")
		if world_node:
			var cam_y = world_node.camera_y
			# 鍙嚮涓浉鏈轰腑蹇冧笂涓?500 鍍忕礌鑼冨洿鍐呯殑鐩爣 (灞忓箷楂樺害绾?800)
			if abs(area.global_position.y - cam_y) > 500:
				return false

	if area.is_in_group("enemies"):
		return area.get("player_lane") == sender_player_id
	if area.is_in_group("fireballs"):
		return area.get("target_player_id") == sender_player_id
	return false

func _create_circle_polygon(radius: float, segments: int) -> PackedVector2Array:
	var points = PackedVector2Array()
	for i in range(segments):
		var angle = (i * 2.0 * PI) / segments
		points.append(Vector2(cos(angle) * radius, sin(angle) * radius))
	return points

func _create_spiral_polygon(radius: float, segments: int) -> PackedVector2Array:
	var points = PackedVector2Array()
	for i in range(segments):
		var angle = (i * 2.0 * PI) / segments
		var r = radius if i % 2 == 0 else radius * 0.6
		points.append(Vector2(cos(angle) * r, sin(angle) * r))
	return points

func _on_area_entered_custom(area):
	if _should_hit_area(area):
		if area.has_method("take_damage"):
			var damage = 10
			if type == ChargePattern.SPIRAL:
				damage = 25
			elif type == ChargePattern.MINE:
				damage = 50 # 蓄力地雷伤害更高
				_spawn_explosion()
			area.take_damage(damage, sender_player_id, 0)

		if type == ChargePattern.LASER:
			return

		hits_left -= 1
		if hits_left <= 0:
			if type == ChargePattern.SWARM:
				var tween = create_tween()
				tween.tween_property(self, "scale", Vector2.ZERO, 0.1)
				tween.tween_callback(queue_free)
			elif type != ChargePattern.LASER and type != ChargePattern.WAVE:
				queue_free()

func _spawn_explosion():
	if explosion_scene:
		var explosion = explosion_scene.instantiate()
		explosion.global_position = global_position
		explosion.explosion_scale = 4.0 # 蓄力地雷爆炸更大
		get_parent().add_child(explosion)
