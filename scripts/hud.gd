extends Control

@onready var main_hbox = $InfoPanel/Margin/MainHBox
@onready var left_vbox = $InfoPanel/Margin/MainHBox/PortraitContainer
@onready var stats_vbox = $InfoPanel/Margin/MainHBox/StatsVBox
@onready var hearts_container = $InfoPanel/Margin/MainHBox/StatsVBox/HeartsContainer
@onready var portrait_bg = $InfoPanel/Margin/MainHBox/PortraitContainer/PortraitBG
@onready var portrait_rect = $InfoPanel/Margin/MainHBox/PortraitContainer/PortraitBG/PortraitRect
@onready var charge_bars = [
	$InfoPanel/Margin/MainHBox/StatsVBox/ChargeSegments/Bar1,
	$InfoPanel/Margin/MainHBox/StatsVBox/ChargeSegments/Bar2,
	$InfoPanel/Margin/MainHBox/StatsVBox/ChargeSegments/Bar3
]
@onready var bomb_label = Label.new()
@onready var combo_label = Label.new()

var combo_timer: SceneTreeTimer
var current_level: int = 0
var current_level_percent: float = 0.0
var is_charging: bool = false
var current_charge_percent: float = 0.0 # 0.0 to 1.0 relative to unlocked max_lv
var max_charge_lv_unlocked: int = 1

func _ready():
	# 强制为蓄力槽添加背景样式
	var bar_bg = StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.1, 0.1, 0.1, 0.6) # 深色背景
	bar_bg.set_corner_radius_all(2)
	
	var bar_fill = StyleBoxFlat.new()
	bar_fill.bg_color = Color(1, 1, 1, 1) # 白色填充
	bar_fill.set_corner_radius_all(2)

	for bar in charge_bars:
		bar.add_theme_stylebox_override("background", bar_bg)
		bar.add_theme_stylebox_override("fill", bar_fill)

	# Add bomb label to stats
	stats_vbox.add_child(bomb_label)
	bomb_label.add_theme_font_size_override("font_size", 14)
	bomb_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# Add combo label
	stats_vbox.add_child(combo_label)
	combo_label.add_theme_font_size_override("font_size", 20)
	combo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	combo_label.text = ""
	
	# Initial charge bar state - Setup fill style if needed, but let's see default first
	_refresh_ui()

func set_layout_mirrored(mirrored: bool):
	if mirrored:
		main_hbox.move_child(left_vbox, 1)
	else:
		main_hbox.move_child(left_vbox, 0)

func update_combo(count: int):
	if count < 2:
		combo_label.text = ""
		return
	combo_label.text = str(count) + " COMBO!"
	var tween = create_tween()
	tween.tween_property(combo_label, "scale", Vector2(1.2, 1.2), 0.1).from(Vector2(1.0, 1.0))
	tween.tween_property(combo_label, "scale", Vector2(1.0, 1.0), 0.1)
	if combo_timer: combo_timer.timeout.disconnect(_clear_combo)
	combo_timer = get_tree().create_timer(1.5)
	combo_timer.timeout.connect(_clear_combo)

func _clear_combo():
	combo_label.text = ""

func update_bombs(count: int):
	bomb_label.text = "BOMB x" + str(count)
	bomb_label.modulate = Color(1, 0.8, 0)

func update_health(health: int):
	for child in hearts_container.get_children(): child.queue_free()
	for i in range(health):
		var heart = Label.new()
		heart.text = "❤"
		heart.add_theme_font_size_override("font_size", 20)
		heart.modulate = Color(1, 0.2, 0.2)
		hearts_container.add_child(heart)

func update_energy(level: int, percent: float):
	current_level = level
	current_level_percent = percent
	_refresh_ui()

func update_charge(level: int, percent: float, max_lv: int):
	max_charge_lv_unlocked = max_lv
	if percent > 0:
		is_charging = true
		current_charge_percent = percent
	else:
		is_charging = false
		current_charge_percent = 0.0
	_refresh_ui()

func _refresh_ui():
	for i in range(3):
		var bar = charge_bars[i]
		
		if is_charging:
			# 蓄力模式：已解锁的段落根据蓄力进度填充
			var total_charge_progress = current_charge_percent * max_charge_lv_unlocked
			var segment_charge = clamp(total_charge_progress - i, 0.0, 1.0)
			
			if i < max_charge_lv_unlocked:
				bar.value = segment_charge
				# 正在填充中的颜色：白色
				bar.modulate = Color(1, 1, 1, 1.0) 
				if segment_charge >= 1.0:
					# 充满变色
					if i == 0: bar.modulate = Color(1, 1, 0) # Lv1: Yellow
					elif i == 1: bar.modulate = Color(0, 1, 1) # Lv2: Cyan
					elif i == 2: bar.modulate = Color(1, 0, 1) # Lv3: Purple
			else:
				# 等级未到，蓄力时依然保持不可用的灰色
				bar.value = 0
				bar.modulate = Color(0.15, 0.15, 0.15, 0.4)
		else:
			# 非蓄力模式：显示 Level 解锁进度
			if i < current_level:
				# 已完全解锁：纯白色块
				bar.value = 1.0
				bar.modulate = Color(1, 1, 1, 1.0)
			elif i == current_level:
				# 正在解锁中：显示进度条
				bar.value = current_level_percent
				bar.modulate = Color(1, 1, 1, 0.7) # 稍微暗一点表示未激活但正在解锁
			else:
				# 锁定：深灰色
				bar.value = 0
				bar.modulate = Color(0.15, 0.15, 0.15, 0.4)

func set_portrait(path: String):
	if path == "" or not ResourceLoader.exists(path):
		portrait_rect.visible = false
		return
	var tex = load(path)
	if tex:
		portrait_rect.texture = tex
		portrait_rect.visible = true
	else:
		portrait_rect.visible = false
