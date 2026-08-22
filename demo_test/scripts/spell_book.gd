class_name SpellBook
extends RefCounted

## 神文录数据管理（提示词 2）：10 槽位 = 2 古代神（不可删）+ 8 玩家神（局内画纹绑定）。
## v1 数值写死；存档 user://spell_book.json。
## 接口对齐《开发提示词_神文录.md》提示词 2。

const SAVE_PATH := "user://spell_book.json"
const SLOT_ORDER: Array[String] = [
	"ancient_1", "ancient_2",
	"player_1", "player_2", "player_3", "player_4",
	"player_5", "player_6", "player_7", "player_8",
]

## 古代神效果：ancient_1 = 回溯（对应现有「时」）；ancient_2 待策划定（空串占位）
const ANCIENT_1_EFFECT := "recall"
const ANCIENT_2_EFFECT := ""

var slots := {}  # slot_id -> {is_ancient, bound, pattern: Array[Vector2]|null, effect_id: String|""}

func _init() -> void:
	if not load_from_disk():
		_default_slots()

## —— 查询 ——

func get_all_slots() -> Array:
	var out: Array = []
	for id in SLOT_ORDER:
		if slots.has(id):
			out.append(get_slot(id))
	return out

func get_slot(slot_id: String) -> Dictionary:
	if not slots.has(slot_id):
		return {}
	var s: Dictionary = slots[slot_id]
	return {
		"slot_id": slot_id,
		"is_ancient": bool(s["is_ancient"]),
		"bound": bool(s["bound"]),
		"pattern": _copy_pattern(s["pattern"]),
		"effect_id": String(s["effect_id"]),
	}

## —— 绑定 / 解绑 ——

## 找第一个未绑定的玩家槽位绑定纹路与效果（绑定后自动存档）
func bind_spell(pattern: Array[Vector2], effect_id: String) -> bool:
	if pattern.size() < 2 or effect_id.is_empty():
		return false
	for id in SLOT_ORDER:
		var s: Dictionary = slots[id]
		if not bool(s["is_ancient"]) and not bool(s["bound"]):
			s["pattern"] = _copy_pattern(pattern)
			s["effect_id"] = effect_id
			s["bound"] = true
			save()
			return true
	return false  # 8 个玩家槽全满

## 删除绑定（古代神不可删，返回 false）；纹路释放后可重新画、重新绑定
func unbind_spell(slot_id: String) -> bool:
	if not slots.has(slot_id):
		return false
	var s: Dictionary = slots[slot_id]
	if bool(s["is_ancient"]):
		return false
	s["pattern"] = null
	s["effect_id"] = ""
	s["bound"] = false
	save()
	return true

## —— 识别 ——

## 用识别器比对所有已绑定槽位的纹路，返回最佳匹配
## {"match": bool, "similarity": float, "slot_id": String, "effect_id": String}
func find_spell(pattern: Array[Vector2], recognizer: SpellRecognizer) -> Dictionary:
	var best_sim := -1.0
	var best_id := ""
	var best_effect := ""
	for id in SLOT_ORDER:
		var s: Dictionary = slots[id]
		if not bool(s["bound"]) or s["pattern"] == null:
			continue
		var sim: float = recognizer.score(pattern, s["pattern"])
		if sim > best_sim:
			best_sim = sim
			best_id = id
			best_effect = String(s["effect_id"])
	if best_id.is_empty() or best_sim < SpellRecognizer.MATCH_THRESHOLD:
		return {"match": false, "similarity": maxf(best_sim, 0.0),
			"slot_id": "", "effect_id": ""}
	return {"match": true, "similarity": best_sim,
		"slot_id": best_id, "effect_id": best_effect}

## 返回还没被绑定的效果 ID（供随机绑定抽选）
func get_unbound_effects(all_effects: Array) -> Array:
	var used := {}
	for id in SLOT_ORDER:
		var s: Dictionary = slots[id]
		if bool(s["bound"]) and not String(s["effect_id"]).is_empty():
			used[String(s["effect_id"])] = true
	var out: Array = []
	for e in all_effects:
		if not used.has(String(e)):
			out.append(e)
	return out

## —— 存档 ——

func save() -> bool:
	var data := {"slots": {}}
	for id in SLOT_ORDER:
		var s: Dictionary = slots[id]
		var entry := {
			"is_ancient": bool(s["is_ancient"]),
			"bound": bool(s["bound"]),
			"effect_id": String(s["effect_id"]),
		}
		if s["pattern"] is Array and (s["pattern"] as Array).size() > 0:
			var pts: Array = []
			for p in s["pattern"]:
				pts.append([p.x, p.y])
			entry["pattern"] = pts
		data["slots"][id] = entry
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data))
	f.close()
	return true

## 读档（提示词 2 的 load()——GDScript 内置 load() 同名冲突，改名 load_from_disk）
func load_from_disk() -> bool:
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return false
	var j: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (j is Dictionary) or not (j as Dictionary).has("slots"):
		return false
	var loaded: Dictionary = (j as Dictionary)["slots"]
	var out := {}
	for id in SLOT_ORDER:
		if not loaded.has(id):
			return false  # 结构不完整 → 重置默认
		var e: Dictionary = loaded[id]
		var pattern = null
		if e.has("pattern") and e["pattern"] is Array:
			var pts: Array[Vector2] = []
			for p in e["pattern"]:
				if p is Array and (p as Array).size() >= 2:
					pts.append(Vector2(float(p[0]), float(p[1])))
			if pts.size() >= 2:
				pattern = pts
		out[id] = {
			"is_ancient": bool(e.get("is_ancient", false)),
			"bound": bool(e.get("bound", false)) and pattern != null,
			"pattern": pattern,
			"effect_id": String(e.get("effect_id", "")),
		}
	slots = out
	return true

## —— 内部 ——

func _default_slots() -> void:
	slots = {
		"ancient_1": {"is_ancient": true, "bound": true,
			"pattern": _gen_hui_pattern(), "effect_id": ANCIENT_1_EFFECT},
		"ancient_2": {"is_ancient": true, "bound": true,
			"pattern": _gen_cross_pattern(), "effect_id": ANCIENT_2_EFFECT},
	}
	for i in range(1, 9):
		slots["player_%d" % i] = {"is_ancient": false, "bound": false,
			"pattern": null, "effect_id": ""}

func _copy_pattern(p) -> Array[Vector2]:
	var out: Array[Vector2] = []
	if p is Array:
		for v in p:
			out.append(v)
	return out

## 「回」字单笔画模板：外圈方 斜入内圈方环（一笔连画）
func _gen_hui_pattern() -> Array[Vector2]:
	var outer := [Vector2(0.08, 0.08), Vector2(0.92, 0.08),
		Vector2(0.92, 0.92), Vector2(0.08, 0.92), Vector2(0.08, 0.08)]
	var inner := [Vector2(0.32, 0.32), Vector2(0.68, 0.32),
		Vector2(0.68, 0.68), Vector2(0.32, 0.68), Vector2(0.32, 0.32)]
	var pts: Array[Vector2] = []
	_walk_polygon(outer, 7, pts)
	_walk_polygon(inner, 5, pts)
	return pts

## 「十」字单笔画模板：横 → 提笔连竖（占位给 ancient_2，效果待策划定）
func _gen_cross_pattern() -> Array[Vector2]:
	var pts: Array[Vector2] = []
	_walk_polygon([Vector2(0.05, 0.30), Vector2(0.95, 0.30)], 6, pts)
	_walk_polygon([Vector2(0.50, 0.05), Vector2(0.50, 0.95)], 6, pts)
	return pts

## 沿多边形边插值采样（一笔连画，不断笔）
func _walk_polygon(corners: Array, per_edge: int, out: Array[Vector2]) -> void:
	if corners.size() < 2:
		return
	for i in range(1, corners.size()):
		var a: Vector2 = corners[i - 1]
		var b: Vector2 = corners[i]
		for k in range(per_edge):
			out.append(a.lerp(b, float(k) / float(per_edge)))
	out.append(corners[corners.size() - 1])
