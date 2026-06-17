extends "res://scripts/base_player.gd"
# 这是一个通用的 Player 脚本，用于没有专门子类实现的角色。
# 它继承自 BasePlayer，并使用基础的蓄力攻击和视觉逻辑。

func _ready():
	super._ready()
	# 如果是 Arthur 角色但使用的是通用场景，我们可以动态改变其蓄力行为
	if character_data.get("display_name", "") == "剑修·Arthur":
		# 这里可以做一些动态调整，或者建议为 Arthur 也创建一个专门的场景/子类
		pass

# 通用角色通常直接使用 character_data 中定义的蓄力类型
func _execute_charge_shoot(level: int):
	var main = get_tree().root.find_child("Main", true, false)
	if main and main.has_method("spawn_charge_attack"):
		var charge_type = character_data.get("charge_type", "WAVE")
		_spawn_charge_wave(main, charge_type)
		
		get_tree().create_timer(0.3).timeout.connect(func(): 
			if is_inside_tree():
				_spawn_charge_wave(main, charge_type)
		)
