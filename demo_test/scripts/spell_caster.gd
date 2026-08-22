class_name SpellCaster
extends RefCounted

## 咒语效果执行层（BUG-08 v0.3 对齐：删 v2 火/风，加「斩」万象斩）

var main

func _init(m) -> void:
	main = m

## 执行咒语。id: shi / zan
func cast(id: String) -> void:
	match id:
		"shi":
			_cast_shi()
		"zan":
			_cast_zan()

func _cast_shi() -> void:
	# 时之回溯：无视时钟充能直接放（消耗时间值已由 Main 扣除）
	main.start_rewind_from_spell()

func _cast_zan() -> void:
	# 万象斩：全屏所有怪 -30 HP，直接结算（不走标记流程）
	var died: Array = []
	for e in main.enemies:
		if e.dead:
			continue
		e.hp -= 30.0
		if e.hp <= 0.0:
			died.append(e)
	main.kill_list(died)
	main.flash_t = main.FLASH_TIME
	main.zan_t = 0.8
	main.zan_red = true
	main.zan_text = "斬·萬象"
	AudioMgr.play("burst", 0.85, -2.0)
