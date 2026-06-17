extends Area2D

@export var speed: float = 800.0
@export var damage: int = 1
var player_id: int = 1
var bullet_index: int = 0

func _ready():
	_setup_shadow()
	if has_node("Sprite2D"):
		var sprite = $Sprite2D
		# 如果编辑器中没有设置纹理，才加载默认子弹图集
		if sprite.texture == null:
			sprite.texture = load("res://assets/characters/jianxiu/bullet.png")
			sprite.hframes = 8
			sprite.vframes = 4
			sprite.frame = bullet_index
		
		# 涓嶅啀寮哄埗閲嶇疆 scale 涓?1.0锛屽皧閲嶇紪杈戝櫒涓殑璁剧疆
		# 涓嶅啀寮哄埗璁剧疆 frame锛岄櫎闈炴槸浣跨敤浜嗛粯璁ゅ浘闆?

	# 缁熶竴瀛愬脊鏍硅妭鐐圭缉鏀句负 1.0
	scale = Vector2(1.0, 1.0)

func _process(delta):
	position.y -= speed * delta

	# Get world reference to check camera position
	var world = get_tree().root.find_child("World", true, false)
	if world and "camera_y" in world:
		# Remove bullet if it goes far above the camera
		if position.y < world.camera_y - 400:
			queue_free()
	else:
		# Fallback cleanup
		if position.y < -10000:
			queue_free()

func _on_area_entered(area):
	if area.is_in_group("enemies") or area.is_in_group("fireballs"):
		if area.has_method("take_damage"):
			# First hit in a chain starts at combo 0
			area.take_damage(damage, player_id, 0)

		# 瀛愬脊纰版挒鍚庢秷澶?
		queue_free()

func _setup_shadow():
	# Visual effect: Simple elliptical shadow for the bullet
	var shadow = Polygon2D.new()
	shadow.name = "BulletShadow"
	
	# Create an ellipse shape
	var points = PackedVector2Array()
	var segments = 12
	var radius_x = 10.0
	var radius_y = 5.0
	for i in range(segments):
		var angle = (float(i) / segments) * TAU
		points.append(Vector2(cos(angle) * radius_x, sin(angle) * radius_y))
	
	shadow.polygon = points
	shadow.color = Color(0, 0, 0, 0.3) # Semi-transparent black
	shadow.z_index = -1 # Behind the bullet
	
	# Position the shadow slightly below the bullet
	shadow.position = Vector2(0, 15)
	
	add_child(shadow)
