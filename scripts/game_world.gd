extends Node2D

@export var enemy_scene: PackedScene

@onready var background = $Background
@onready var bg_texture = $Background/BG_Texture
var camera_y: float = 400.0
var game_time: float = 0.0
var bg_scroll_speed: float = 50.0 # Speed of background scrolling

var cloud_spawn_timer: float = 0.0
var cloud_texture: Texture2D = preload("res://素材/backgrounds/cloud_clean.png")

var fever_spawned: bool = false
var death_spawned: bool = false
var lane_width: float = 800.0 # Default fallback

func update_lane_info(width: float):
	lane_width = width

func _ready():
	# Create some stars for scrolling effect
	for i in range(80):
		var star = ColorRect.new()
		star.size = Vector2(2, 2)
		star.position = Vector2(randf_range(0, 1600), randf_range(-400, 400))
		star.color = Color(1, 1, 1, randf_range(0.3, 0.8))
		$Background/Stars.add_child(star)

	# Initial spawn of a few clouds so the screen isn't empty at the start
	for i in range(5):
		_spawn_cloud()
		var clouds = $Background/Clouds.get_children()
		if clouds.size() > 0:
			var cloud = clouds[-1]
			cloud.position.y = randf_range(-400, 400)

func _process(delta):
	game_time += delta
	_check_special_spawns()

	# 璁╄儗鏅妭鐐瑰缁堣窡闅忕浉鏈哄瀭鐩翠綅缃?
	if background:
		background.position.y = camera_y

	# Scroll background texture using region_rect
	if bg_texture and bg_texture is Sprite2D:
		# 鎴戜滑閫氳繃淇敼 region_rect 鏉ュ疄鐜版棤闄愬钩閾烘粴鍔?
		var r = bg_texture.region_rect
		r.position.y -= bg_scroll_speed * delta
		
		# 淇濇寔鏁板€煎湪涓€涓悎鐞嗚寖鍥村唴
		if r.position.y < -2048:
			r.position.y += 2048
		bg_texture.region_rect = r

	# Scroll stars
	for star in $Background/Stars.get_children():
		star.position.y += 100 * delta
		if star.position.y > 500:
			star.position.y = -500
			star.position.x = randf_range(0, 1600)

	# Cloud logic
	cloud_spawn_timer -= delta
	if cloud_spawn_timer <= 0:
		_spawn_cloud()
		cloud_spawn_timer = randf_range(1.5, 4.0)

	if has_node("Background/Clouds"):
		for cloud in $Background/Clouds.get_children():
			# 杩欓噷鐨?cloud position 鏄浉瀵逛簬 background 鑺傜偣鐨?
			# 鐢变簬 background 鑺傜偣宸茬粡璺熼殢浜?camera_y锛屾墍浠?cloud 鍙渶瑕佸鐞嗚嚜韬殑鍋忕Щ
			cloud.position.y += bg_scroll_speed * 0.4 * delta
			if cloud.position.y > 1000:
				cloud.queue_free()

func _spawn_cloud():
	if not has_node("Background/Clouds"):
		return
	var cloud = Sprite2D.new()
	cloud.texture = cloud_texture

	# Configure sprite sheet for cloud.png (assuming it's a grid of clouds)
	# Assuming a 2x2 or 3x3 grid based on typical cloud sprite sheets. Let's try 2x2 first, or you can adjust.
	# Actually, I will set hframes=2, vframes=2 and pick a random frame.
	cloud.hframes = 2
	cloud.vframes = 2
	cloud.frame = randi() % 4

	# Random position above screen
	cloud.position = Vector2(randf_range(-100, 1700), randf_range(-400, -200))
	# Random scale for varied cloud sizes (reduced size as requested)
	var scale_val = randf_range(0.4, 0.8)
	cloud.scale = Vector2(scale_val, scale_val)
	# Randomly flip the cloud horizontally
	cloud.flip_h = randf() > 0.5
	# Random opacity for depth - made more opaque (solid) as requested
	cloud.modulate = Color(1, 1, 1, randf_range(0.7, 1.0))
	$Background/Clouds.add_child(cloud)

func _check_special_spawns():
	# Fever ball after 30-40 seconds
	if not fever_spawned and game_time > 35.0:
		fever_spawned = true
		_spawn_special_enemy(true, false) # Fever ball

	# Death (Grim Reaper) after 100 seconds
	if not death_spawned and game_time > 100.0:
		death_spawned = true
		_spawn_special_enemy(false, true) # Death

func _spawn_special_enemy(is_fever: bool, is_death: bool):
	# Spawn for both lanes
	var centers = [lane_width / 2.0, 800.0 + lane_width / 2.0]
	for x_center in centers:
		var enemy = enemy_scene.instantiate()
		enemy.position = Vector2(x_center, camera_y - 500)
		if is_fever:
			enemy.is_fever_ball = true
			enemy.health = 3
		if is_death:
			enemy.is_death = true
			enemy.health = 999
			enemy.modulate = Color(0, 0, 0) # Black for Death
			enemy.scale = Vector2(3, 3)
		add_child(enemy)

func _on_spawn_timer_timeout():
	# Randomly pick a formation type
	var formation_type = randi() % 5 # Increased to 5 to include RAVEN

	if formation_type == 4:
		# Special RAVEN formation
		spawn_raven_formation(0.0) # Lane 1
		spawn_raven_formation(800.0) # Lane 2
	else:
		# Spawn for Lane 1 (centered on Lane 1)
		spawn_formation(formation_type, randf_range(lane_width * 0.2, lane_width * 0.8))
		# Spawn for Lane 2 (centered on Lane 2, which starts at 800)
		spawn_formation(formation_type, 800.0 + randf_range(lane_width * 0.2, lane_width * 0.8))

	# Randomize next spawn time between 5.0 and 8.0 seconds to reduce frequency
	$SpawnTimer.wait_time = randf_range(5.0, 8.0)

func spawn_raven_formation(x_offset):
	var group_size = 1 # Reduced from 2
	var delay_between = 0.5
	
	# Left side group
	for i in range(group_size):
		var enemy = enemy_scene.instantiate()
		enemy.movement_type = 4 # RAVEN
		enemy.health = 3
		enemy.speed = 180.0
		# Added small random X offset to prevent perfect overlap on spawn
		var start_x = x_offset + lane_width * 0.1 + randf_range(-30, 30)
		enemy.position = Vector2(start_x, camera_y - 500)
		enemy.spawn_offset = i * delay_between
		add_child(enemy)
		
	# Right side group
	for i in range(group_size):
		var enemy = enemy_scene.instantiate()
		enemy.movement_type = 4 # RAVEN
		enemy.health = 3
		enemy.speed = 180.0
		# Added small random X offset
		var start_x = x_offset + lane_width * 0.9 + randf_range(-30, 30)
		enemy.position = Vector2(start_x, camera_y - 500)
		enemy.spawn_offset = i * delay_between
		add_child(enemy)

func spawn_formation(type, x_pos):
	var base_group_size = 5
	var delay_between = 0.5

	# Specialized parameters for STRAIGHT
	if type == 0:
		base_group_size = 8 # More enemies
		delay_between = 0.3 # Tighter packing
	
	for i in range(base_group_size):
		var enemy = enemy_scene.instantiate()
		# Vary health
		if i == 0:
			enemy.health = 1
		else:
			enemy.health = randi_range(2, 4)

		# Chance to be in a bubble (reduced for STRAIGHT to keep it clean)
		var bubble_chance = 0.1 if type == 0 else 0.2
		if randf() < bubble_chance:
			enemy.is_bubble = true

		enemy.position = Vector2(x_pos, camera_y - 500)
		
		match type:
			0: # STRAIGHT
				enemy.movement_type = 0
				enemy.speed = 280.0 # Much faster
				enemy.spawn_offset = i * delay_between
			1: # SINE
				enemy.movement_type = 1
				enemy.amplitude = 150.0
				enemy.frequency = 3.0
				enemy.speed = 120.0
				enemy.spawn_offset = i * delay_between
			2: # ZIGZAG
				enemy.movement_type = 2
				enemy.amplitude = 180.0
				enemy.frequency = 2.0
				enemy.speed = 100.0
				enemy.spawn_offset = i * delay_between
			3: # CIRCLE
				enemy.movement_type = 3
				enemy.amplitude = 100.0
				enemy.frequency = 4.0
				enemy.speed = 90.0
				enemy.spawn_offset = i * delay_between

		add_child(enemy)

func spawn_enemy(x_pos):
	# Keep this for backward compatibility or single spawns
	var enemy = enemy_scene.instantiate()
	enemy.position = Vector2(x_pos, camera_y - 400)
	add_child(enemy)
