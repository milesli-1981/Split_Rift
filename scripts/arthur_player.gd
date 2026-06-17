extends "res://scripts/base_player.gd"
# 移除 class_name

# Arthur (剑修·Arthur) 特定的攻击逻辑
func _execute_charge_shoot(level: int):
	var main = get_tree().root.find_child("Main", true, false)
	if main and main.has_method("spawn_charge_attack"):
		# Arthur 使用 GROW (逐渐变长的剑意)
		var charge_type = "GROW"
		_spawn_charge_wave(main, charge_type)
