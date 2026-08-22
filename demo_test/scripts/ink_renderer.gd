class_name InkRenderer
extends RefCounted
## 水墨笔触渲染器（静态，纯函数）。
## 从任意 CanvasItem._draw 内调用 draw_brush_path(c, pts, ...)。
## 样式来源：传入 style 参数，或默认读 InkStyle.current（autoload）。

static func hash_f(i: int) -> float:
	return fposmod(sin(float(i) * 12.9898) * 43758.5453, 1.0)

static func dedup(pts: PackedVector2Array, min_d: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		if out.is_empty() or p.distance_to(out[out.size() - 1]) >= min_d:
			out.append(p)
	return out

static func smooth_path(pts: PackedVector2Array, iters: int) -> PackedVector2Array:
	var cur := pts
	for _k in iters:
		var m := cur.size()
		if m < 3:
			break
		var nxt := PackedVector2Array()
		nxt.append(cur[0])
		for i in m - 1:
			var a: Vector2 = cur[i]
			var b: Vector2 = cur[i + 1]
			nxt.append(a.lerp(b, 0.25))
			nxt.append(a.lerp(b, 0.75))
		nxt.append(cur[m - 1])
		cur = nxt
	return cur

static func tangent(pts: PackedVector2Array, i: int) -> Vector2:
	var m := pts.size()
	var a: Vector2 = pts[maxi(0, i - 1)]
	var b: Vector2 = pts[mini(m - 1, i + 1)]
	var d := b - a
	return d.normalized() if d.length() > 0.0001 else Vector2.RIGHT

static func ribbon_poly(pts: PackedVector2Array, widths: Array, scale: float, jitter: float, seed: float) -> PackedVector2Array:
	var m := pts.size()
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for i in m:
		var dir := tangent(pts, i)
		var nrm := Vector2(-dir.y, dir.x)
		var w: float = float(widths[i]) * scale
		var h := fposmod(sin(float(i) * 7.13 + seed * 3.7) * 937.7, 1.0)
		var j := (h * 2.0 - 1.0) * w * jitter
		left.append(pts[i] + nrm * (w + j))
		right.append(pts[i] - nrm * (w - j))
	var poly := PackedVector2Array()
	for p in left:
		poly.append(p)
	for i in range(right.size() - 1, -1, -1):
		poly.append(right[i])
	return poly

static func poly(c: CanvasItem, pts: PackedVector2Array, col: Color) -> void:
	var tri := Geometry2D.triangulate_polygon(pts)
	if tri != null and not tri.is_empty():
		c.draw_polygon(pts, PackedColorArray([col]))
		return
	# 自交兜底：拆段四边形（共享边无缝）
	var half := pts.size() / 2
	if pts.size() >= 4 and pts.size() % 2 == 0:
		for i in half - 1:
			var quad := PackedVector2Array([
				pts[i], pts[i + 1],
				pts[2 * half - 2 - i], pts[2 * half - 1 - i]])
			c.draw_polygon(quad, PackedColorArray([col]))

static func draw_brush_path(c: CanvasItem, pts: PackedVector2Array, alpha: float, red: bool, boost := 1.0, style: InkBrushStyle = null) -> void:
	var m := pts.size()
	if m < 2:
		return
	var s: InkBrushStyle = style if style != null else InkStyle.current
	if s == null:
		return
	var sp := smooth_path(dedup(pts, 0.75), maxi(s.smooth_iters, 0))
	m = sp.size()
	if m < 2:
		return
	var seed := float(int(pts[0].x) % 977) * 0.37 + float(int(pts[0].y) % 761) * 0.11
	var ink_col: Color = s.red_color if red else s.ink_color
	var paper: Color = s.paper_color
	# 宽度：起笔饱满 → 收笔尖锋，带墨量波动
	var widths: Array = []
	for i in m:
		var t := float(i) / float(m - 1)
		var wbase := lerpf(s.width_start, s.width_end, pow(t, s.width_taper)) * boost
		var wob := sin(t * s.width_wobble_freq + seed) * 1.1 \
			+ (hash_f(i * 3 + int(seed * 10.0)) * 2.0 - 1.0) * s.width_wobble_amp
		widths.append(maxf(wbase + wob, 1.0))
	# 1) 淡墨晕边（黑→灰→纸白的灰层）
	poly(c, ribbon_poly(sp, widths, s.halo_scale, s.halo_jitter, seed),
		Color(ink_col.r, ink_col.g, ink_col.b, alpha * s.halo_alpha))
	# 2) 主体墨带
	poly(c, ribbon_poly(sp, widths, 1.0, s.edge_jitter, seed),
		Color(ink_col.r, ink_col.g, ink_col.b, alpha * s.body_alpha))
	# 3) 枯笔飞白：纸色细丝透底
	var fb_step := maxi(s.feibai_step, 1)
	for i in m:
		if i % fb_step != 0:
			continue
		var h := hash_f(i * 11 + int(seed * 5.0))
		if h < 1.0 - s.feibai_chance:
			continue
		var dir := tangent(sp, i)
		var nrm := Vector2(-dir.y, dir.x)
		var off := nrm * (float(widths[i]) * (h * 1.6 - 0.8))
		var len := lerpf(s.feibai_len_min, s.feibai_len_max, h)
		c.draw_line(sp[i] + off, sp[i] + off + dir * len,
			Color(paper.r, paper.g, paper.b, s.feibai_alpha * (0.4 + 0.6 * h)), 1.0 + h)
	# 4) 溅墨点
	var sp_step := maxi(s.splatter_step, 1)
	for i in m:
		if i % sp_step != 1:
			continue
		var h := hash_f(i * 7 + int(seed * 13.0) + 51)
		if h < 1.0 - s.splatter_chance:
			continue
		var dir := tangent(sp, i)
		var nrm := Vector2(-dir.y, dir.x)
		var side := 1.0 if h > 0.65 else -1.0
		var pp := sp[i] + nrm * (float(widths[i]) + 2.0 + h * s.splatter_spread) * side
		c.draw_circle(pp, lerpf(s.splatter_size_min, s.splatter_size_max, h),
			Color(ink_col.r, ink_col.g, ink_col.b, alpha * s.splatter_alpha * (0.4 + 0.6 * h)))
	# 5) 扫帚收锋：末端散开细丝
	var tail: Vector2 = sp[m - 1]
	var tdir := tangent(sp, m - 1)
	for k in maxi(s.tail_strands, 0):
		var h := hash_f(k * 17 + int(seed * 7.0) + 99)
		var ang := tdir.angle() + (h * 2.0 - 1.0) * s.tail_spread
		var d := Vector2(cos(ang), sin(ang))
		var len := lerpf(s.tail_len_min, s.tail_len_max, h)
		c.draw_line(tail, tail + d * len,
			Color(ink_col.r, ink_col.g, ink_col.b, alpha * s.tail_alpha * (0.4 + 0.6 * h)), 1.0 + h * 1.2)
