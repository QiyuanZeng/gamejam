extends Node
## 神文录数据层测试：默认槽位 / 绑定解绑 / find_spell 识别（含归一化抗噪）/ 存档往返。

var fails: Array[String] = []

func _ready() -> void:
	randomize()
	# 清掉可能残留的存档，保证默认态
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SpellBook.SAVE_PATH))
	var book := SpellBook.new()

	# —— 1. 默认槽位 ——
	_chk(book.get_all_slots().size() == 10, "default 10 slots")
	var a1: Dictionary = book.get_slot("ancient_1")
	_chk(a1["is_ancient"] and a1["bound"] and a1["effect_id"] == "recall"
		and (a1["pattern"] as Array).size() > 0, "ancient_1 = recall bound")
	var a2: Dictionary = book.get_slot("ancient_2")
	_chk(a2["is_ancient"] and a2["bound"] and a2["effect_id"] == "",
		"ancient_2 bound, effect 待定（空串占位）")
	var p1: Dictionary = book.get_slot("player_1")
	_chk(not p1["bound"] and (p1["pattern"] as Array).size() == 0 and p1["effect_id"] == "",
		"player_1 unbound by default")

	# —— 2. 绑定 ——
	var vline := _stroke(Vector2(0, 0), Vector2(0, 100))
	_chk(book.bind_spell(vline, "thunder"), "bind vertical -> player_1")
	var got: Dictionary = book.get_slot("player_1")
	_chk(got["bound"] and got["effect_id"] == "thunder"
		and (got["pattern"] as Array).size() == vline.size(), "player_1 thunder bound")
	_chk(not book.bind_spell(_stroke(Vector2(0, 0), Vector2(10, 10)), ""),
		"empty effect_id rejected")

	# —— 3. 填满 8 个玩家槽 ——
	var fx := ["quake", "flood", "sword", "domain", "alpha", "treant", "meteor"]
	var hline := _stroke(Vector2(0, 50), Vector2(100, 50))
	for i in fx.size():
		_chk(book.bind_spell(hline, fx[i]), "fill player_%d = %s" % [i + 2, fx[i]])
	_chk(not book.bind_spell(hline, "extra"), "9th bind fails (slots full)")

	# —— 4. 解绑 ——
	_chk(not book.unbind_spell("ancient_1"), "ancient_1 cannot unbind")
	_chk(not book.unbind_spell("ancient_2"), "ancient_2 cannot unbind")
	_chk(book.unbind_spell("player_1"), "player_1 unbind ok")
	_chk(book.bind_spell(vline, "thunder"), "rebind after unbind")

	# —— 5. find_spell（缩放/平移/抖动后仍命中） ——
	var rec := SpellRecognizer.new()
	var noisy_v := _jitter(vline, 2.0, Vector2(300, 200), 5.0)
	var r1: Dictionary = book.find_spell(noisy_v, rec)
	_chk(bool(r1["match"]) and r1["effect_id"] == "thunder" and r1["slot_id"] == "player_1",
		"find vertical -> player_1 thunder (sim %.2f)" % float(r1["similarity"]))
	# 「回」模板坐标在 [0,1] 区间，抖动须按比例缩（≈2%）
	var noisy_hui := _jitter(a1["pattern"], 1.4, Vector2(50, 50), 0.025)
	var r2: Dictionary = book.find_spell(noisy_hui, rec)
	_chk(bool(r2["match"]) and r2["slot_id"] == "ancient_1" and r2["effect_id"] == "recall",
		"find hui -> ancient_1 recall (sim %.2f)" % float(r2["similarity"]))
	var r3: Dictionary = book.find_spell(_zigzag(), rec)
	_chk(not bool(r3["match"]), "zigzag no match (sim %.2f)" % float(r3["similarity"]))

	# —— 6. get_unbound_effects ——
	var pool := ["recall", "thunder", "quake", "flood", "meteor", "newone"]
	var free_fx: Array = book.get_unbound_effects(pool)
	_chk(free_fx.size() == 1 and free_fx[0] == "newone",
		"unbound effects = [newone], got %s" % str(free_fx))

	# —— 7. 存档往返 ——
	_chk(book.save(), "save ok")
	var book2 := SpellBook.new()
	var p1b: Dictionary = book2.get_slot("player_1")
	_chk(p1b["bound"] and p1b["effect_id"] == "thunder"
		and (p1b["pattern"] as Array).size() == vline.size(), "load roundtrip player_1")
	_chk(book2.get_slot("ancient_1")["effect_id"] == "recall", "load roundtrip ancient_1")
	_chk(book2.get_slot("player_8")["effect_id"] == "meteor", "load roundtrip player_8")

	# —— 清理 ——
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SpellBook.SAVE_PATH))
	var book3 := SpellBook.new()
	_chk(not book3.get_slot("player_1")["bound"], "file removed -> defaults")

	for f in fails:
		print("FAIL: ", f)
	print("SPELLBOOK ", "PASS" if fails.is_empty() else "FAIL")
	get_tree().quit(1 if not fails.is_empty() else 0)

## 两端点插值成一笔
func _stroke(a: Vector2, b: Vector2, n := 24) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for i in n:
		out.append(a.lerp(b, float(i) / float(n - 1)))
	return out

## 缩放 + 平移 + 逐点抖动（考验归一化链）
func _jitter(pts: Array, s: float, off: Vector2, j: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for p in pts:
		out.append(Vector2(p.x * s + off.x + randf_range(-j, j),
			p.y * s + off.y + randf_range(-j, j)))
	return out

## 锯齿线（不匹配任何模板）
func _zigzag() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for i in 12:
		out.append(Vector2(float(i) * 9.0, 30.0 if i % 2 == 0 else -30.0))
	return out

func _chk(cond: bool, msg: String) -> void:
	print(("ok   " if cond else "BAD  "), msg)
	if not cond:
		fails.append(msg)
