extends Area2D

enum AttackPattern { WAVE, LASER, MINE, SPIRAL, SWARM, PIG, PLANE, RABBIT }

@export var type: AttackPattern = AttackPattern.WAVE
@export var sender_player_id: int = 1
@export var target_player_id: int = 2 # The player it is attacking
@export var lifetime: float = 2.5
@export var explosion_scene: PackedScene = preload("res://scenes/Explosion.tscn")

var source_player: Node2D 
var direction: Vector2 = Vector2.DOWN
var speed: float = 300.0
var time_passed: float = 0.0
var hits_left: int = 1 
var laser_damage_timer: float = 0.0
var laser_damage_interval: float = 0.1 
var mine_damage_timer: float = 0.0
var mine_damage_interval: float = 0.15 

var laser_sprite: Sprite2D = null
var laser_anim_timer: float = 0.0

# Emerging effect for PLANE
var is_emerging: bool = false
var emerging_progress: float = 0.0
var emerging_duration: float = 0.8

@onready var polygon = get_node_or_null("Polygon2D")
@onready var sprite = get_node_or_null("Sprite2D")
@onready var collision = get_node_or_null("CollisionShape2D")

func _ready():
	# Make collision shape unique to avoid resource sharing issues
	if collision and collision.shape:
		collision.shape = collision.shape.duplicate()

	# Connect body_entered to hit players (since these are all opponent attacks)
	body_entered.connect(_on_body_entered)

	# Pattern specific initialization
	match type:
		AttackPattern.SWARM:
			lifetime = 4.5 
			hits_left = 3 
			speed = 750.0 
		AttackPattern.MINE:
			lifetime = 2.0 
			speed = 0.0 
		AttackPattern.SPIRAL:
			lifetime = 4.0
			hits_left = 10 
			speed = 500.0
		AttackPattern.LASER:
			z_index = -5 
		AttackPattern.PIG:
			lifetime = 3.0
			speed = 800.0 
		AttackPattern.PLANE:
			lifetime = 5.0
			speed = 2200.0 # 飞行速度大幅提升
			hits_left = 1 # 恢复为 1，确保击中敌人后立即消失
			direction = Vector2.UP # Plane moves UP from bottom of opponent's screen
		AttackPattern.RABBIT:
			lifetime = 4.0
			speed = 600.0

	# Always connect area_entered to hit enemies/fireballs
	area_entered.connect(_on_area_entered_custom)

	_setup_visuals()

func _setup_visuals():
	if sprite:
		sprite.visible = false
	if polygon:
		polygon.visible = true
		
	# These are all obstacles sent to opponent
	match type:
		AttackPattern.WAVE:
			if polygon:
				polygon.polygon = PackedVector2Array([Vector2(-30, 0), Vector2(30, 0), Vector2(40, 20), Vector2(-40, 20)])
			modulate = Color(0.2, 0.8, 1.0, 1.0)
			if collision and collision.shape is RectangleShape2D:
				collision.shape.size = Vector2(60, 20)
		AttackPattern.LASER:
			if polygon:
				polygon.polygon = PackedVector2Array([Vector2(-15, -100), Vector2(15, -100), Vector2(15, 100), Vector2(-15, 100)])
			modulate = Color(1, 0.2, 0.2, 1.0) 
			if collision and collision.shape is RectangleShape2D:
				collision.shape.size = Vector2(30, 200)
		AttackPattern.MINE:
			if polygon:
				polygon.polygon = _create_circle_polygon(40, 16)
			modulate = Color(1, 0.5, 0)
			if collision and collision.shape:
				var circle = CircleShape2D.new()
				circle.radius = 40
				collision.shape = circle
		AttackPattern.SPIRAL:
			if polygon:
				polygon.polygon = _create_spiral_polygon(30, 16)
			modulate = Color(0.8, 0, 1)
			if collision and collision.shape:
				var circle = CircleShape2D.new()
				circle.radius = 30
				collision.shape = circle
		AttackPattern.SWARM:
			if polygon:
				polygon.polygon = PackedVector2Array([Vector2(-10, -10), Vector2(10, -10), Vector2(0, 20)])
			modulate = Color(1, 1, 0)
			if collision and collision.shape:
				collision.shape.size = Vector2(20, 20)
		AttackPattern.PIG:
			if polygon:
				polygon.polygon = _create_circle_polygon(25, 8)
			modulate = Color(1.0, 0.7, 0.7) 
			if collision and collision.shape:
				var circle = CircleShape2D.new()
				circle.radius = 25
				collision.shape = circle
		AttackPattern.PLANE:
			if polygon:
				polygon.visible = false
			if sprite:
				sprite.visible = true
				if not sprite.texture:
					sprite.texture = load("res://素材/effects/extra_attack.png")
				
				# 比例进一步缩小 (从 0.18 缩小到 0.12)
				sprite.scale = Vector2(0.12, 0.12) 
				
				if collision and collision.shape is RectangleShape2D:
					var tex_size = sprite.texture.get_size()
					collision.shape.size = tex_size * sprite.scale
				
				# 重构贴合逻辑
				# 我们增加一个微调值 tip_adj，防止贴图顶部有透明留白导致缩放后看起来“离得远”
				var tip_adj = 0.08 # 增加一点初始可见度
				var tex_height = sprite.texture.get_size().y * sprite.scale.y
				sprite.position = Vector2(0, tex_height * (0.5 - tip_adj)) 
				
				# Add sliding & boundary clipping shader
				var shader = Shader.new()
				shader.code = """
shader_type canvas_item;
uniform float min_x = -10000.0;
uniform float max_x = 10000.0;
uniform float reveal_height = 0.0;

varying float world_x;

void vertex() {
    world_x = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).x;
}

void fragment() {
    vec4 col = texture(TEXTURE, UV);
    // 裁剪逻辑：UV.y 从 0 到 1。
    // 我们希望只显示 UV.y 较小的部分。
    if (UV.y > reveal_height) {
        col.a = 0.0;
    }
    COLOR = col;
}
"""
				var mat = ShaderMaterial.new()
				mat.shader = shader
				sprite.material = mat
				mat.set_shader_parameter("reveal_height", tip_adj) # 初始只显示剑尖一点点
				
				var clip_min = 50.0
				var clip_max = 750.0
				if sender_player_id == 1:
					clip_min = 850.0
					clip_max = 1550.0
				mat.set_shader_parameter("min_x", clip_min)
				mat.set_shader_parameter("max_x", clip_max)
				
				is_emerging = true
				emerging_progress = 0.0
				emerging_duration = 0.6 # 稍微加快显现速度
				z_index = 30 # 确保在最上层
				
				# sprite.position.y 已经设置好了
				print("ExtraAttack PLANE spawned at: ", global_position, " target: ", target_player_id, " sender: ", sender_player_id)
				pass
					
			modulate = Color(1.0, 1.0, 1.0) # Reset modulate for sprite to show original colors
		AttackPattern.RABBIT:
			if polygon:
				polygon.polygon = PackedVector2Array([Vector2(-15, 20), Vector2(15, 20), Vector2(15, -10), Vector2(5, -40), Vector2(0, -10), Vector2(-5, -40), Vector2(-15, -10)])
			modulate = Color(1.0, 1.0, 1.0) 
			if collision and collision.shape:
				collision.shape.size = Vector2(30, 60)
				collision.position.y = -10

func _process(delta):
	_update_movement(delta)

	if time_passed >= lifetime:
		if type == AttackPattern.MINE:
			_spawn_explosion()
		queue_free()
		return

	if laser_sprite and type == AttackPattern.LASER:
		laser_anim_timer += delta
		if laser_anim_timer >= 0.1:
			laser_anim_timer = 0.0
			laser_sprite.frame = (laser_sprite.frame + 1) % (laser_sprite.hframes * laser_sprite.vframes)

	if type != AttackPattern.LASER:
		_check_screen_boundaries()

func _check_screen_boundaries():
	# 定义分屏的中轴线
	var divider_x = 800.0
	
	# 如果是攻击 P1 (左屏)
	if target_player_id == 1:
		# 飞向右边越界 (进入 P2 屏幕) 或飞向左边太远
		if global_position.x > divider_x - 20 or global_position.x < -100:
			queue_free()
	# 如果是攻击 P2 (右屏)
	else:
		# 飞向左边越界 (进入 P1 屏幕) 或飞向右边太远
		if global_position.x < divider_x + 20 or global_position.x > 1700:
			queue_free()
	
	# 通用的上下越界检查 (离开垂直战斗区域太远)
	var main = get_tree().root.find_child("Main", true, false)
	if main:
		var cam_y = main.world.camera_y
		if abs(global_position.y - cam_y) > 1000:
			queue_free()

func _physics_process(delta):
	if type == AttackPattern.LASER or type == AttackPattern.MINE:
		_handle_continuous_damage(delta)

func _update_movement(delta):
	time_passed += delta
	match type:
		AttackPattern.WAVE:
			position += direction * speed * delta
		AttackPattern.LASER:
			_update_laser_position()
		AttackPattern.MINE:
			_update_mine_visuals(delta)
		AttackPattern.SPIRAL:
			_update_spiral_movement(delta)
		AttackPattern.SWARM:
			_track_player(delta)
		AttackPattern.PIG:
			_track_player(delta, 1.5) 
			position.x += sin(time_passed * 5.0) * 100.0 * delta
		AttackPattern.PLANE:
			var main = get_tree().root.find_child("Main", true, false)
			# Calculate actual movement vector based on rotation (moving towards its local UP)
			var move_dir = Vector2.UP.rotated(rotation)
			
			if is_emerging:
				emerging_progress += delta / emerging_duration
				var tex_height = sprite.texture.get_size().y * sprite.scale.y
				var tip_adj = 0.08
				
				if sprite and sprite.material:
					var current_reveal = lerp(tip_adj, 1.0, emerging_progress)
					sprite.material.set_shader_parameter("reveal_height", current_reveal)
					sprite.position.y = tex_height * (0.5 - current_reveal)
				
				if emerging_progress >= 1.0:
					is_emerging = false
					z_index = 0
					if sprite and sprite.material:
						sprite.material.set_shader_parameter("reveal_height", 1.0)
			else:
				position += move_dir * speed * delta
		AttackPattern.RABBIT:
			position += direction * speed * delta
			var jump_height = 400.0
			var jump_freq = 6.0
			position.y -= abs(sin(time_passed * jump_freq)) * jump_height * delta
			rotation = sin(time_passed * jump_freq) * 0.3

func _update_laser_position():
	if source_player and source_player.visible:
		var lane_offset = 800.0 if sender_player_id == 1 else -800.0
		global_position.x = source_player.global_position.x + lane_offset
		global_position.y = source_player.global_position.y - 30
	else:
		queue_free()

func _update_mine_visuals(delta):
	scale = Vector2.ONE * (1.0 + 0.15 * sin(time_passed * 10.0))
	rotation += delta * 2.0

func _update_spiral_movement(delta):
	position += direction * speed * delta
	position.x += cos(time_passed * 12.0) * 400.0 * delta
	rotation += delta * 10.0

func _track_player(delta, steering_weight: float = 3.0):
	var main = get_tree().root.find_child("Main", true, false)
	if main:
		var target = main.get_player(target_player_id)
		if target and target.visible:
			var target_dir = (target.global_position - global_position).normalized()
			direction = direction.lerp(target_dir, steering_weight * delta).normalized()
		position += direction * (speed * 1.5) * delta

func _handle_continuous_damage(delta):
	if type == AttackPattern.LASER:
		_update_laser_position()
		laser_damage_timer -= delta
		if laser_damage_timer <= 0:
			laser_damage_timer = laser_damage_interval
			_apply_continuous_damage(5, 1)
	elif type == AttackPattern.MINE:
		mine_damage_timer -= delta
		if mine_damage_timer <= 0:
			mine_damage_timer = mine_damage_interval
			_apply_continuous_damage(15, 2)

func _apply_continuous_damage(enemy_damage: int, player_damage: int):
	var targets = get_overlapping_areas()
	for area in targets:
		if _should_hit_area(area):
			if area.has_method("take_damage"):
				area.take_damage(enemy_damage, sender_player_id, 0)

	var bodies = get_overlapping_bodies()
	for body in bodies:
		if body.is_in_group("players") and body.player_id == target_player_id:
			if body.has_method("take_damage"):
				body.take_damage(player_damage)

func _should_hit_area(area: Area2D) -> bool:
	if not (area.is_in_group("enemies") or area.is_in_group("fireballs")):
		return false
	
	# 增加垂直范围检查，防止击中屏幕上方过远（未出现）或下方的目标
	var main = get_tree().root.find_child("Main", true, false)
	if main:
		var world_node = main.get_node_or_null("MainLayout/BattleArea/ViewportContainer1/Viewport1/World")
		if world_node:
			var cam_y = world_node.camera_y
			# 鍙嚮涓浉鏈轰腑蹇冧笂涓?550 鍍忕礌鑼冨洿鍐呯殑鐩爣 (闅滅鐗╅€氬父浠庝笂鏂瑰嚭鐜帮紝绋嶆斁瀹借寖鍥?
			if abs(area.global_position.y - cam_y) > 550:
				return false

	if area.is_in_group("enemies"):
		return area.get("player_lane") == target_player_id
	if area.is_in_group("fireballs"):
		# 淇锛氭敾鍑诲簲璇ュ嚮涓敾鍑昏嚜宸辩殑寮瑰箷锛堝嵆鐩爣鐜╁鍙戝嚭鐨勫脊骞曪級
		# 鐩爣鐜╁鍙戝嚭鐨勫脊骞曪紝鍏?target_player_id 搴旇鏄?sender_player_id
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
	if is_emerging:
		return
		
	if _should_hit_area(area):
		if area.has_method("take_damage"):
			var damage = 10
			if type == AttackPattern.SPIRAL:
				damage = 25
			elif type == AttackPattern.MINE:
				damage = 40 # 增加地雷直接碰撞伤害
				_spawn_explosion()
			area.take_damage(damage, sender_player_id, 0)

		if type == AttackPattern.LASER:
			return

		hits_left -= 1
		if hits_left <= 0:
			if type == AttackPattern.SWARM:
				var tween = create_tween()
				tween.tween_property(self, "scale", Vector2.ZERO, 0.1)
				tween.tween_callback(queue_free)
			elif type != AttackPattern.LASER and type != AttackPattern.WAVE:
				queue_free()
		elif type == AttackPattern.PLANE:
			# 特殊处理 PLANE：即使 hits_left > 0，在击中非火球目标时也应消失
			# 如果你希望它能穿透火球但撞到敌人就消失，可以在这里加判断
			queue_free()

func _on_body_entered(body):
	if is_emerging:
		return
		
	if body.is_in_group("players") and body.player_id == target_player_id:
		if body.has_method("take_damage"):
			var damage = 3
			if type == AttackPattern.SPIRAL:
				damage = 4 
			elif type == AttackPattern.MINE:
				damage = 5 # 地雷对玩家伤害较高
				_spawn_explosion()
			body.take_damage(damage)
		if type != AttackPattern.LASER: 
			queue_free()

func _spawn_explosion():
	if explosion_scene:
		var explosion = explosion_scene.instantiate()
		explosion.global_position = global_position
		explosion.explosion_scale = 3.0 # 地雷爆炸大一些
		get_parent().add_child(explosion)
