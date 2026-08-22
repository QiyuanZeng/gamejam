class_name SpellCaster
extends RefCounted

## 咒语效果执行层（老版 SPELL 系统移植，适配新版 Main 接口）。

var main

func _init(m) -> void:
	main = m

## 执行咒语。id: shi / huo / feng
func cast(id: String) -> void:
	match id:
		"shi":
			_cast_shi()
		"huo":
			_cast_huo()
		"feng":
			_cast_feng()

func _cast_shi() -> void:
	# 回溯：无视时钟充能直接放（消耗时间值已由 Main 扣除）
	main.start_rewind_from_spell()

func _cast_huo() -> void:
	# 爆：玩家周围 300px 内敌人 -60 HP，直接结算（不走标记）
	var p: Player = main.player
	var died: Array = []
	for e in main.enemies:
		if e.dead:
			continue
		if e.position.distance_to(p.position) < 300.0 + float(e.cfg.radius):
			e.hp -= 60.0
			if e.hp <= 0.0:
				died.append(e)
	main.kill_list(died)
	main.flash_t = main.FLASH_TIME
	main.zan_t = 0.5
	main.zan_red = false
	main.zan_text = "火 · 爆"
	AudioMgr.play("burst", 1.0, -3.0)

func _cast_feng() -> void:
	# 疾：移速 +80% 3s，墨值瞬回 15
	var p: Player = main.player
	p.speed_buff_t = 3.0
	p.ink = minf(Player.INK_MAX, p.ink + 15.0)
	main.zan_t = 0.5
	main.zan_red = false
	main.zan_text = "风 · 疾"
	AudioMgr.play("dash", 1.0, -4.0)
