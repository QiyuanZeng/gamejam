class_name SpellRecognizer
extends RefCounted

## $1 Unistroke Recognizer —— 单笔画模板匹配（神文录任务 1：双阈值版）
## 输入：鼠标轨迹点序列；输出：{match, similarity, spell_id}。
## 阈值规则（提示词 1）：
##   similarity ≥ 0.80 → match=true，触发已有技能
##   所有模板 < 0.50   → match=false，判"新纹路"（可触发绑定，由调用方按 similarity 判定）
##   0.50 ~ 0.80       → match=false，无效（"看不懂"）

const RESAMPLE_N := 64
const BOUND := 250.0
const MATCH_THRESHOLD := 0.80       # 触发已有技能
const NEW_PATTERN_THRESHOLD := 0.50 # 低于此值才算新纹路

## 咒语定义：id → { name(显示字), time_cost, 描述 }
## BUG-08 v0.3 对齐：删 v2 遗留的火/风，加「斩」万象斩
const SPELLS := {
	"shi": {"name": "时", "time_cost": 150.0, "desc": "时之回溯 · 重演最近 5 笔斩击"},
	"zan": {"name": "斩", "time_cost": 120.0, "desc": "万象斩 · 全屏所有怪 -30 HP"},
}

## 内置模板（assets/spell_templates.json 存在时优先加载，同 id 多个样本）
## 坐标任意（识别前统一归一化），内置样本沿用 [0,1] 区间。
var _templates: Dictionary = {
	"shi": [
		[Vector2(0.50, 0.05), Vector2(0.50, 0.95)],  # 竖
		[Vector2(0.10, 0.30), Vector2(0.90, 0.30)],  # 横
		[Vector2(0.50, 0.10), Vector2(0.50, 0.50), Vector2(0.10, 0.50), Vector2(0.90, 0.50)],  # 十字
	],
	"zan": [
		[Vector2(0.05, 0.50), Vector2(0.95, 0.50)],  # 左→右横扫（万象斩主笔）
		[Vector2(0.05, 0.40), Vector2(0.95, 0.60)],  # 斜扫（变体）
		[Vector2(0.10, 0.50), Vector2(0.50, 0.20), Vector2(0.90, 0.50)],  # 上弧扫
	],
}

func _init() -> void:
	# 神文录新格式：[{"spell_id": "...", "points": [[x,y], ...]}, ...]（数组每项一个样本）
	var f := FileAccess.open("res://assets/spell_templates.json", FileAccess.READ)
	if f != null:
		var j: Variant = JSON.parse_string(f.get_as_text())
		if j is Array and not (j as Array).is_empty():
			var loaded: Dictionary = {}
			for entry in j:
				if entry is Dictionary and entry.has("spell_id") and entry.has("points"):
					var sid := String(entry["spell_id"])
					var pts: Array[Vector2] = []
					for p in entry["points"]:
						if p is Array and (p as Array).size() >= 2:
							pts.append(Vector2(float(p[0]), float(p[1])))
					if pts.size() >= 2:
						if not loaded.has(sid):
							loaded[sid] = []
						loaded[sid].append(pts)
			if not loaded.is_empty():
				_templates = loaded

## 识别一笔（对内置/JSON 模板库）。返回 {"match": bool, "similarity": float, "spell_id": String}
## match=false 时 spell_id 为空；similarity 恒为最佳值（供调用方判断 <0.50 新纹路）。
func recognize(points: Array[Vector2]) -> Dictionary:
	if points.size() < 8:
		return {"match": false, "similarity": 0.0, "spell_id": ""}
	var best_id := ""
	var best_sim := -1.0
	for id in _templates:
		for raw_tpl in _templates[id]:
			var sim := score(points, raw_tpl)
			if sim > best_sim:
				best_sim = sim
				best_id = String(id)
	if best_id.is_empty() or best_sim < MATCH_THRESHOLD:
		return {"match": false, "similarity": maxf(best_sim, 0.0), "spell_id": ""}
	return {"match": true, "similarity": best_sim, "spell_id": best_id}

## 两笔相似度（0~1）：神文录槽位比对入口，template 为任意原始点序列
func score(points: Array[Vector2], template: Array) -> float:
	if points.size() < 2 or template.size() < 2:
		return 0.0
	var tpl: Array[Vector2] = []
	for p in template:
		tpl.append(p if p is Vector2 else Vector2(float(p[0]), float(p[1])))
	var a := _normalize(points)
	var b := _normalize(tpl)
	return clampf(1.0 - _path_distance(a, b) / (0.5 * sqrt(2.0 * BOUND * BOUND)), 0.0, 1.0)

## 归一化预处理链：重采样 → 旋转 → 缩放 → 平移
func _normalize(points: Array[Vector2]) -> Array[Vector2]:
	var pts := _resample(points, RESAMPLE_N)
	pts = _rotate_to_zero(pts)
	pts = _scale_to_square(pts)
	return _translate_to_origin(pts)

## 重采样为 N 个等距点
func _resample(points: Array[Vector2], n: int) -> Array[Vector2]:
	var out: Array[Vector2] = [points[0]]
	if points.size() < 2:
		while out.size() < n:
			out.append(points[0])
		return out
	var total := 0.0
	for i in range(1, points.size()):
		total += points[i].distance_to(points[i - 1])
	var step := total / float(n - 1)
	var remain := step
	var prev := points[0]
	for i in range(1, points.size()):
		var cur := points[i]
		var seg := cur.distance_to(prev)
		if seg < 0.0001:
			continue
		var dir := (cur - prev) / seg
		var travelled := 0.0
		while remain <= seg - travelled:
			travelled += remain
			out.append(prev + dir * travelled)
			remain = step
		remain -= (seg - travelled)
		prev = cur
	while out.size() < n:
		out.append(points[points.size() - 1])
	return out

## 旋转：使首点与重心连线转到 0 度（消除方向/旋转差异）
func _rotate_to_zero(points: Array[Vector2]) -> Array[Vector2]:
	var c := Vector2.ZERO
	for p in points:
		c += p
	c /= float(points.size())
	var ang := atan2(c.y - points[0].y, c.x - points[0].x)
	return _rotate_by(points, -ang)

func _rotate_by(points: Array[Vector2], ang: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for p in points:
		out.append(Vector2(p.x * cos(ang) - p.y * sin(ang), p.x * sin(ang) + p.y * cos(ang)))
	return out

## 缩放到 BOUND 方形包围盒（保持纵横比）
func _scale_to_square(points: Array[Vector2]) -> Array[Vector2]:
	var minx := INF
	var miny := INF
	var maxx := -INF
	var maxy := -INF
	for p in points:
		minx = minf(minx, p.x)
		miny = minf(miny, p.y)
		maxx = maxf(maxx, p.x)
		maxy = maxf(maxy, p.y)
	var w := maxf(maxx - minx, 1.0)
	var h := maxf(maxy - miny, 1.0)
	var s := BOUND / maxf(w, h)
	var out: Array[Vector2] = []
	for p in points:
		out.append((p - Vector2(minx, miny)) * s)
	return out

func _translate_to_origin(points: Array[Vector2]) -> Array[Vector2]:
	var c := Vector2.ZERO
	for p in points:
		c += p
	c /= float(points.size())
	var out: Array[Vector2] = []
	for p in points:
		out.append(p - c)
	return out

func _path_distance(a: Array[Vector2], b: Array[Vector2]) -> float:
	var sum := 0.0
	for i in a.size():
		sum += a[i].distance_to(b[i])
	return sum / float(a.size())
