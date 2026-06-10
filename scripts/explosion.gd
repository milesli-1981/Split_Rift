extends Area2D

@export var damage: int = 1
@export var lifetime: float = 0.5
@export var explosion_scale: float = 3.0

var source_player_id: int = 0
var combo_count: int = 0

func _ready():
	# Visual effect removed as requested (only damage remains)
	visible = false
	
	# Match the collision shape radius * scale for immediate check
	_apply_damage()

	# Self-destruct after a very short time (just enough to process collisions)
	get_tree().create_timer(0.1).timeout.connect(queue_free)

func _apply_damage():
	# Use a circle query to be more reliable than get_overlapping_areas
	# which can be finicky in the first few frames
	var space_state = get_world_2d().direct_space_state
	var query = PhysicsShapeQueryParameters2D.new()

	# Match the collision shape radius * scale
	var shape = CircleShape2D.new()
	shape.radius = 60.0 * explosion_scale

	query.shape = shape
	query.transform = global_transform
	query.collision_mask = 1 # Enemies should be on layer 1
	query.collide_with_areas = true
	query.collide_with_bodies = false

	var results = space_state.intersect_shape(query)
	for result in results:
		var collider = result.collider
		if collider.is_in_group("enemies"):
			if collider.has_method("take_damage"):
				collider.take_damage(damage, source_player_id, combo_count)
