class_name SpellRecognizer
extends RefCounted

## $1 Unistroke Recognizer —— 单笔画模板匹配
## 输入：鼠标轨迹点序列；输出：命中咒语 id + 置信度（0~1）。

const RESAMPLE_N := 64
const BOUND := 250.0

## 咒语定义：id → { name(显示字), time_cost, 描述 }
## BUG-08 v0.3 对齐：删 v2 遗留的火/风，加「斩」万象斩
const SPELLS := {
	"shi": {"name": "时", "time_cost": 150.0, "desc": "时之回溯 · 重演最近 5 笔斩击"},
	"zan": {"name": "斩", "time_cost": 120.0, "desc": "万象斩 · 全屏所有怪 -30 HP"},
}

## 内置模板（策划可替换成 assets/spell_templates.json，每个字 3~5 个样本）
## 坐标均为 [0,1] 归一化，识别时自动缩放。
## BUG-08：删 v2 火/风，加「斩」横扫笔画（左到右横扫 = 万象斩）
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
	var f := FileAccess.open("res://assets/spell_templates.json", FileAccess.READ)
	if f != null:
		var j: Variant = JSON.parse_string(f.get_as_text())
		if j is Dictionary and j.has("templates"):
			_templates = j["templates"]

## 识别一笔。points 为原始屏幕坐标序列，返回 {id, conf, name}
func recognize(points: Array[Vector2]) -> Dictionary:
	if points.size() < 8:
		return {}
	var pts := _resample(points, RESAMPLE_N)
	pts = _rotate_to_zero(pts)
	pts = _scale_to_square(pts)
	pts = _translate_to_origin(pts)
	var best_id := ""
	var best_dist := INF
	for id in _templates:
		for raw_tpl in _templates[id]:
			var tpl := _resample(raw_tpl, RESAMPLE_N)
			tpl = _rotate_to_zero(tpl)
			tpl = _scale_to_square(tpl)
			tpl = _translate_to_origin(tpl)
			var d := _path_distance(pts, tpl)
			if d < best_dist:
				best_dist = d
				best_id = id
	if best_id.is_empty():
		return {}
	var conf := 1.0 - best_dist / (0.5 * sqrt(2.0 * BOUND * BOUND))
	if conf < 0.55:  # BUG-08 放宽阈值 0.68→0.55
		return {}
	return {"id": best_id, "conf": conf, "name": SPELLS[best_id]["name"]}

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
