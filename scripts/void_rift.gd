extends Node2D

var target_id: int
var extra_type: String
var sender_player: Node2D
var projectile_data: Dictionary = {}

@onready var anim_appear1 = $appear
@onready var anim_idle1 = $idle
@onready var anim_disappear1 = $disappear

@onready var anim_appear2 = $appear2
@onready var anim_idle2 = $idle2
@onready var anim_disappear2 = $disappear2

var selected_anim_set = 1 # 1 or 2

var current_anim_appear: AnimatedSprite2D
var current_anim_idle: AnimatedSprite2D
var current_anim_disappear: AnimatedSprite2D

enum State { APPEAR, IDLE, DISAPPEAR }
var current_state = State.APPEAR

var frame_timer: float = 0.0
var spawned_projectile: bool = false

func _ready():
	# Randomly select an animation set
	selected_anim_set = 1 if randf() > 0.5 else 2
	
	if selected_anim_set == 1:
		current_anim_appear = anim_appear1
		current_anim_idle = anim_idle1
		current_anim_disappear = anim_disappear1
	else:
		current_anim_appear = anim_appear2
		current_anim_idle = anim_idle2
		current_anim_disappear = anim_disappear2
	
	# Random scale (0.8 - 1.0 of base scale)
	var random_scale = randf_range(0.8, 1.0)
	scale = Vector2(1.8, 1.8) * random_scale
	
	# Hide all initially
	anim_appear1.visible = false
	anim_idle1.visible = false
	anim_disappear1.visible = false
	anim_appear2.visible = false
	anim_idle2.visible = false
	anim_disappear2.visible = false
	
	# Connect signals
	current_anim_appear.animation_finished.connect(_on_appear_finished)
	current_anim_disappear.animation_finished.connect(_on_disappear_finished)
	
	# Start with appear
	_aim_at_target()
	_switch_to_state(State.APPEAR)
	
	z_index = 25 # Ensure it's on top of everything

func _aim_at_target():
	var main = get_tree().root.find_child("Main", true, false)
	if main:
		var target = main.get_player(target_id)
		if target:
			var diff = target.global_position - global_position
			# Vector2.UP is (0, -1), so we need to add PI/2 to rotate the \"up\" vector towards the target
			rotation = diff.angle() + PI/2
	else:
		# Fallback to random if main not found
		rotation = randf_range(deg_to_rad(-20), deg_to_rad(20))

func _switch_to_state(new_state):
	current_state = new_state
	frame_timer = 0.0
	
	# Reset visibility for all
	anim_appear1.visible = false
	anim_idle1.visible = false
	anim_disappear1.visible = false
	anim_appear2.visible = false
	anim_idle2.visible = false
	anim_disappear2.visible = false
	
	# Show current active animation
	current_anim_appear.visible = (new_state == State.APPEAR)
	current_anim_idle.visible = (new_state == State.IDLE)
	current_anim_disappear.visible = (new_state == State.DISAPPEAR)
	
	match new_state:
		State.APPEAR:
			current_anim_appear.play("default")
		State.IDLE:
			current_anim_idle.play("default")
			if not spawned_projectile:
				_spawn_projectile()
		State.DISAPPEAR:
			current_anim_disappear.play("default")

func _process(delta):
	if current_state == State.IDLE:
		frame_timer += delta
		# Stay in idle for a short fixed duration (e.g. 0.5s) before disappearing
		if frame_timer >= 0.5:
			_switch_to_state(State.DISAPPEAR)

func _on_appear_finished():
	if current_state == State.APPEAR:
		_switch_to_state(State.IDLE)

func _on_disappear_finished():
	if current_state == State.DISAPPEAR:
		queue_free()

func _spawn_projectile():
	spawned_projectile = true
	var main = get_tree().root.find_child("Main", true, false)
	if main and main.has_method("send_opponent_attack_direct"):
		# Pass rotation to match the rift's orientation
		main.send_opponent_attack_direct(target_id, extra_type, global_position, sender_player, true, rotation)
