extends "res://scripts/base_player.gd"

# 女鬼特定的视觉逻辑
func _update_charge_visuals(delta):
	var config = character_data.get("charge_visuals", {})
	if config.is_empty(): return
	var vfx = charge_vfx
	if not vfx: return

	# 处理旋转逻辑
	var rot_speed = config.get("vfx_rotate_speed", 0.0)
	if rot_speed != 0.0 and charge_state != ChargeState.NONE:
		vfx.rotation += rot_speed * delta

	match charge_state:
		ChargeState.NONE:
			vfx.visible = false
		
		ChargeState.CHARGING:
			vfx.visible = config.get("vfx_enabled", true)
			if vfx is AnimatedSprite2D:
				# 女鬼蓄力时根据进度显示帧 (如果使用了专门的 charge 动画)
				if vfx.sprite_frames and vfx.sprite_frames.has_animation("charge"):
					vfx.stop()
					var total_frames = vfx.sprite_frames.get_frame_count("charge")
					var progress = clamp(charge_time / charge_threshold, 0.0, 1.0)
					var buildup_frames = total_frames / 2
					vfx.animation = "charge"
					vfx.frame = int(progress * (buildup_frames - 1))
				elif vfx.sprite_frames and vfx.sprite_frames.has_animation("charging"):
					if vfx.animation != "charging":
						vfx.play("charging")
				else:
					_manual_vfx_charge(vfx, delta)
		
		ChargeState.HOLDING:
			vfx.visible = true
			if vfx is AnimatedSprite2D:
				if vfx.sprite_frames and vfx.sprite_frames.has_animation("holding"):
					if vfx.animation != "holding":
						vfx.play("holding")
				elif vfx.sprite_frames and vfx.sprite_frames.has_animation("charging"):
					# 停在蓄力完成的那一帧
					var total_frames = vfx.sprite_frames.get_frame_count("charging")
					vfx.frame = (total_frames / 2) - 1
		
		ChargeState.RELEASING:
			vfx.visible = true
			if vfx is AnimatedSprite2D:
				if vfx.sprite_frames and vfx.sprite_frames.has_animation("releasing"):
					if vfx.animation != "releasing":
						vfx.play("releasing")
				elif vfx.sprite_frames and vfx.sprite_frames.has_animation("charging"):
					# 播放后半段动画
					if vfx.animation != "charging":
						vfx.play("charging")
				else:
					_manual_vfx_release(vfx, config, delta)

# 女鬼特定的攻击逻辑
func _execute_charge_shoot(_level: int):
	var main = get_tree().root.find_child("Main", true, false)
	if main and main.has_method("spawn_charge_attack"):
		# 女鬼使用 LASER
		var charge_type = "LASER"
		_spawn_charge_wave(main, charge_type)
