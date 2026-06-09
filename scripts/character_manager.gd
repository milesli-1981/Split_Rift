extends Node

# Character Data Structure
const CHARACTERS = {
	"Arthur": {
		"display_name": "剑修·Arthur",
		"portrait_path": "res://素材/ui/avatar_jianxiu.png",
		"speed": 550.0,
		"fire_rate": 0.25,
		"charge_speed": 1.3,
		"charge_type": "GROW",
		"charge_desc": "青莲剑歌：释放逐渐变长的青芒剑意，凌空而上，破尽万法",
		"extra_type": "PLANE",
		"color": Color(0.8, 0.9, 1.0),
		"bullet_index": 18,
		"sprite_frames_path": "res://素材/characters/jianxiu/Arthur_SpriteFrames.tres",
		"sprite_scale": Vector2(1.0, 1.0), # 基础缩放
		"anim_speed": 0.15,
		"frame_offsets": [],
		"charge_visuals": {
			"sprite_path": "res://素材/characters/jianxiu/charge_effect.png",
			"hframes": 2,
			"vframes": 2,
			"scale_multiplier": 1.0,
			"frame_offsets": [
				Vector2(-30, 0),
				Vector2(18, 10),
				Vector2(-28, 30),
				Vector2(16, 26),
			],
			"vfx_enabled": true,
			"vfx_rotate_speed": 2.0,
			"release_cooldown": 0.5,
			"release_anim_speed": 0.05
		}
	},
	"Sprites": {
		"display_name": "斯普莱茨",
		"speed": 400.0,
		"fire_rate": 0.1,
		"charge_speed": 1.5,
		"charge_type": "LASER",
		"charge_desc": "冲击波：发射覆盖半个屏幕宽度的巨大扇形能量波",
		"extra_type": "PIG",
		"color": Color(1.0, 1.0, 0.5),
		"bullet_index": 4, # 黄色点状
		"sprite_frames_path": "res://素材/characters/jianxiu/Arthur_SpriteFrames.tres",
		"anim_speed": 0.15,
		"charge_visuals": {
			"sprite_path": "res://素材/characters/jianxiu/charge_effect.png",
			"hframes": 2,
			"vframes": 2,
			"scale_multiplier": 1.0
		}
	},
	"YanYang": {
		"display_name": "艳艳艳",
		"speed": 450.0,
		"fire_rate": 0.15,
		"charge_speed": 0.8,
		"charge_type": "SWARM",
		"charge_desc": "追踪蜂群：瞬间释放大量小型快速追踪弹",
		"extra_type": "RABBIT",
		"color": Color(1.0, 0.5, 0.8),
		"bullet_index": 2, # 粉色点状
		"sprite_frames_path": "res://素材/characters/jianxiu/Arthur_SpriteFrames.tres",
		"anim_speed": 0.15
	},
	"Nanja": {
		"display_name": "纳加蒙加",
		"speed": 400.0,
		"fire_rate": 0.08,
		"charge_speed": 1.3,
		"charge_type": "SPIRAL",
		"charge_desc": "螺旋法球：巨大的法球呈螺旋状扩张落下，占据大量空间",
		"extra_type": "SWARM",
		"color": Color(0.5, 1.0, 0.5),
		"bullet_index": 0, # 绿色点状
		"sprite_frames_path": "res://素材/characters/jianxiu/Arthur_SpriteFrames.tres",
		"anim_speed": 0.15
	},
	"Ran": {
		"display_name": "蓝蓝",
		"speed": 480.0,
		"fire_rate": 0.12,
		"charge_speed": 1.6,
		"charge_type": "MINE",
		"charge_desc": "兔子地雷：在场上布下定时炸弹，爆炸后留有持久伤害区",
		"extra_type": "MINE",
		"color": Color(0.5, 0.5, 1.0),
		"bullet_index": 20, # 蓝色点状
		"sprite_frames_path": "res://素材/characters/jianxiu/Arthur_SpriteFrames.tres",
		"anim_speed": 0.15
	}
}

var p1_choice: String = "Ran"
var p2_choice: String = "Arthur"
var debug_mode: bool = false
