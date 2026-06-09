extends Area2D

@export var damage: int = 1
@export var lifetime: float = 0.5
@export var explosion_scale: float = 3.0

var source_player_id: int = 0
var combo_count: int = 0

func _ready():
	# Visual effect: Simple expansion and fade out
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", Vector2(explosion_scale, explosion_scale), lifetime).from(Vector2(0.5, 0.5))
	tween.tween_property(self, "modulate", Color(2.0, 1.5, 0.5, 0.0), lifetime).from(Color(1.0, 0.6, 0.0, 1.0))

	# Wait a tiny bit for the expansion to cover area before checking damage
	await get_tree().create_timer(0.05).timeout
	_apply_damage()

	# Self-destruct after animation
	await tween.finished
	queue_free()

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
