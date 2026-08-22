class_name SpellLab
extends CanvasLayer
## 咒语调试台（F2）：左侧无限墨画布，右侧实时显示本笔的墨耗与 8 技能匹配度。
## 判定全部走 SpellMatch，与实战同一份算法阈值；本台不扣真实 TV、不影响战局。

signal closed

const PAD_POS := Vector2(12.0, 46.0)
const PAD_SIZE := Vector2(688.0, 590.0)
const PANEL_X := 712.0
const PANEL_W := 428.0
const ROW_H := 22.0
const MATCH_H := 34.0
const MAX_STROKES := 8
const REMATCH_GAP := 120                   # 书写途中重算匹配的最小间隔（ms）
const GRAB_R := 14.0                       # 控制点抓取半径（px）
const EDIT_FILL := 0.55                    # 模板映射到画布时占画布的比例

const INK := Color("#1A1714")
const RED := Color("#C0392B")
const GREY := Color("#4A443C")
const PAPER := Color("#F5F1E8")
const DIM := Color(0.05, 0.045, 0.04, 0.85)

var game                                   # 可选：挂上后读实时 tv_max / 已绑笔形
var skills: Array = []
var strokes: Array[PackedVector2Array] = []
var cur := PackedVector2Array()
var drawing := false
var draw_t := 0.0                          # 本笔书写耗时（子弹时间流逝按它折算）
var last_t := 0.0
var edit_id := ""                          # 正在编辑的固定笔形 id；非空则画布进编辑模式
var edit_pts := PackedVector2Array()       # 编辑中的控制点（画布局部坐标）
var ghost_id := ""                         # 正在描摹参照的固定笔形 id（1/2 切换）
var drag_i := -1                           # 正在拖的控制点下标
var dirty := false                         # 编辑后尚未保存
var reset_armed := false                   # 「全部恢复默认」的二次确认闸
var feat := {}                             # 当前笔画特征（节流重算）
var rows: Array = []                       # 8 技能匹配结果，按得分降序
var _match_t := -9999
var toast_t := 0.0
var toast_text := ""
var font: Font
var board: Control
var pad: Control

class _Board extends Control:
	var lab: SpellLab
	func _draw() -> void:
		if lab != null:
			lab._paint(self)

class _Pad extends Control:
	var lab: SpellLab
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		clip_contents = true
	func _gui_input(event: InputEvent) -> void:
		if lab == null:
			return
		if lab.edit_id != "":
			_edit_input(event)
			return
		if not (event is InputEventMouseButton):
			return
		if event.button_index != MOUSE_BUTTON_LEFT:
			return
		if event.pressed:
			lab.drawing = true
			lab.draw_t = 0.0
			lab.cur = PackedVector2Array([_clamped(get_local_mouse_position())])
		else:
			if lab.drawing and lab.cur.size() >= 2:
				lab.strokes.append(lab.cur)
				lab.last_t = lab.draw_t
				if lab.strokes.size() > SpellLab.MAX_STROKES:
					lab.strokes.remove_at(0)
			lab.drawing = false
			lab.cur = PackedVector2Array()
		lab._refresh(true)
	## 编辑模式：左键拖控制点、点段中把手插点，右键删点。
	func _edit_input(event: InputEvent) -> void:
		if event is InputEventMouseMotion:
			if lab.drag_i >= 0:
				lab.edit_pts[lab.drag_i] = _clamped(get_local_mouse_position())
				lab.dirty = true
				lab._refresh()
			return
		if not (event is InputEventMouseButton):
			return
		var p := _clamped(get_local_mouse_position())
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				lab._edit_press(p)
			else:
				lab.drag_i = -1
				lab._refresh(true)
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			lab._edit_delete(p)
	func _process(delta: float) -> void:
		if lab == null or not lab.drawing:
			return
		lab.draw_t += delta
		var p := _clamped(get_local_mouse_position())
		var last: Vector2 = lab.cur[lab.cur.size() - 1]
		if p.distance_to(last) >= Game.SAMPLE_DIST:
			lab.cur.append(p)
		lab._refresh()
	func _draw() -> void:
		var s := InkStyle.current
		draw_rect(Rect2(Vector2.ZERO, size), s.paper_color if s != null else SpellLab.PAPER)
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.3), false, 1.0)
		if lab == null:
			return
		if lab.edit_id != "":
			lab._paint_edit(self)
			return
		lab._paint_ghost(self)
		var n := lab.strokes.size()
		for i in n:
			var st: PackedVector2Array = lab.strokes[i]
			InkRenderer.draw_brush_path(self, st, 0.28 if i < n - 1 else 0.95, false)
		if lab.cur.size() >= 2:
			InkRenderer.draw_brush_path(self, lab.cur, 0.95, false)
	func _clamped(p: Vector2) -> Vector2:
		return Vector2(clampf(p.x, 4.0, size.x - 4.0), clampf(p.y, 4.0, size.y - 4.0))

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	font = load("res://assets/fonts/MFYueYuan_Noncommercial-Regular.ttf")
	_load_skills()
	board = _Board.new()
	board.lab = self
	board.position = Vector2.ZERO
	board.size = Vector2(1152, 648)
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(board)
	pad = _Pad.new()
	pad.lab = self
	pad.position = PAD_POS
	pad.size = PAD_SIZE
	board.add_child(pad)
	get_tree().create_timer(0.25).timeout.connect(_arm)

var _armed := false

## 台内技能表：挂了战局就镜像战局的（含玩家已绑的 3~8），否则起一份出厂表。
func _load_skills() -> void:
	skills = []
	if game != null:
		for s in game.skills:
			skills.append(s.duplicate())
	else:
		skills = SpellMatch.build_skills()

func _arm() -> void:
	_armed = true

func _refresh(force := false) -> void:
	# $Q 是 O(n²) 双向贪心比对，8 技能约 10ms，跟着每帧重算会拖垮书写手感。
	# 书写途中按 REMATCH_GAP 节流，松笔/清空/录入时强制重算。
	var now := Time.get_ticks_msec()
	if force or now - _match_t >= REMATCH_GAP:
		_match_t = now
		feat = SpellMatch.feature(active_path())
		rows.clear()
		for i in skills.size():
			var s: Dictionary = skills[i]
			rows.append({"s": s, "c": SpellMatch.check(feat, s), "i": i})
		rows.sort_custom(func(a, b): return float(a.c.sim) > float(b.c.sim))
	pad.queue_redraw()
	board.queue_redraw()

func _process(delta: float) -> void:
	if toast_t > 0.0:
		toast_t = maxf(toast_t - delta, 0.0)
		board.queue_redraw()

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	if not event.pressed:
		if event.keycode in [KEY_F2, KEY_ESCAPE]:
			_armed = true   # 开启键松开 → 解除防秒关武装门（只管关闭键）
		return
	if event.keycode != KEY_R:
		reset_armed = false        # 「再按一次 R」只在连按时成立，中间插别的键就作废
	match event.keycode:
		KEY_F2:
			if _armed:
				_on_close()
				get_viewport().set_input_as_handled()
		KEY_ESCAPE:
			if edit_id != "":
				_exit_edit()          # 编辑中先退编辑，别一脚把整个台子踢掉
			elif _armed:
				_on_close()
			get_viewport().set_input_as_handled()
		KEY_C:
			if edit_id != "":
				return
			strokes.clear()
			cur = PackedVector2Array()
			last_t = 0.0
			_toast("已清空")
			_refresh(true)
		KEY_1:
			_toggle_ghost_at(0)
		KEY_2:
			_toggle_ghost_at(1)
		KEY_ENTER, KEY_KP_ENTER:
			_learn_fixed()
		KEY_E:
			_toggle_edit(ghost_id)
		KEY_S:
			_save_edit()
		KEY_R:
			if edit_id != "":
				_reset_edit()
			else:
				_restore_all()
		KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8:
			if edit_id == "":
				_learn(event.keycode - KEY_3 + 2)

# ============================== 固定笔形编辑 ==============================

## 把某个字的控制点映射到画布上，变成可拖的实体点。
func _toggle_edit(id: String) -> void:
	if id == "":
		_toast("先按 1/2 选一个固定笔形，再按 E 精修")
		return
	if edit_id == id:
		_exit_edit()
		return
	edit_id = id
	drag_i = -1
	dirty = false
	edit_pts = _map_to_pad(SpellMatch.ancient_stroke(id))
	_toast("精修「%s」：拖点改形 · 点中把手插点 · 右键删点 · S 保存 · R 出厂 · Esc 退出"
		% _label(id))
	_refresh(true)

func _exit_edit() -> void:
	var was_dirty := dirty
	edit_id = ""
	edit_pts = PackedVector2Array()
	drag_i = -1
	dirty = false
	if was_dirty:
		_toast("已退出编辑（改动未保存）")
	_refresh(true)

## 把模板点等比铺到画布中央，占 EDIT_FILL 的幅面。
func _map_to_pad(ref: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	if ref.size() < 2:
		return out
	var lo := ref[0]
	var hi := ref[0]
	for p in ref:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	var span := hi - lo
	var k: float = minf(PAD_SIZE.x * EDIT_FILL / maxf(span.x, 1.0),
		PAD_SIZE.y * EDIT_FILL / maxf(span.y, 1.0))
	var org := (PAD_SIZE - span * k) * 0.5 - lo * k
	for p in ref:
		out.append(p * k + org)
	return out

## 回写用：平移到原点、等比缩到最长边 60，让存盘数值和出厂形一个量级。
func _to_model(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	if pts.size() < 2:
		return out
	var lo := pts[0]
	var hi := pts[0]
	for p in pts:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	var span := hi - lo
	var k := 60.0 / maxf(maxf(span.x, span.y), 1.0)
	for p in pts:
		out.append((p - lo) * k)
	return out

func _edit_press(p: Vector2) -> void:
	var i := _nearest_point(p)
	if i >= 0:
		drag_i = i
		return
	var m := _nearest_mid(p)
	if m >= 0:
		edit_pts.insert(m + 1, edit_pts[m].lerp(edit_pts[m + 1], 0.5))
		drag_i = m + 1
		dirty = true
		_refresh(true)

func _edit_delete(p: Vector2) -> void:
	if edit_pts.size() <= 2:
		_toast("至少留 2 个点")
		return
	var i := _nearest_point(p)
	if i < 0:
		return
	edit_pts.remove_at(i)
	drag_i = -1
	dirty = true
	_refresh(true)

func _nearest_point(p: Vector2) -> int:
	var best := GRAB_R
	var out := -1
	for i in edit_pts.size():
		var d := p.distance_to(edit_pts[i])
		if d <= best:
			best = d
			out = i
	return out

## 返回段起点下标；命中的是该段中点把手。
func _nearest_mid(p: Vector2) -> int:
	var best := GRAB_R
	var out := -1
	for i in edit_pts.size() - 1:
		var d := p.distance_to(edit_pts[i].lerp(edit_pts[i + 1], 0.5))
		if d <= best:
			best = d
			out = i
	return out

func _save_edit() -> void:
	if edit_id == "":
		return
	var model := _to_model(edit_pts)
	if model.size() < 2:
		_toast("点太少，存不了")
		return
	SpellMatch.set_custom(edit_id, model)
	var err := SpellMatch.save_custom()
	_rebind_fixed(edit_id)
	dirty = false
	_toast("已保存「%s」并落盘，下次开局仍是这个形%s" % [
		_label(edit_id), "" if err == OK else "（写盘失败 %d）" % err])
	_refresh(true)

func _reset_edit() -> void:
	if edit_id == "":
		return
	SpellMatch.set_custom(edit_id, PackedVector2Array())
	SpellMatch.save_custom()
	_rebind_fixed(edit_id)
	edit_pts = _map_to_pad(SpellMatch.default_stroke(edit_id))
	dirty = false
	_toast("「%s」已恢复出厂形" % _label(edit_id))
	_refresh(true)

## 用当前生效的笔形重建该技能的点云，调试台与战局两份都刷。
func _rebind_fixed(id: String) -> void:
	var f := SpellMatch.feature(SpellMatch.ancient_stroke(id))
	if f.is_empty():
		return
	for pool in [skills, (game.skills if game != null else [])]:
		for s in pool:
			if String(s.id) == id:
				s.cloud = f.cloud
				s.bound = true

# ============================== 参照描摹 / 固定笔形录入 ==============================

## 数字键按下标取古代神纹，不写死 id —— 神纹录换人时这里不用跟着改。
func _toggle_ghost_at(slot: int) -> void:
	var ids := SpellMatch.ancient_ids()
	if slot < 0 or slot >= ids.size():
		return
	_toggle_ghost(String(ids[slot]))

## 1/2 切换：把该字当前生效的笔形淡淡铺在画布上当描摹底。
func _toggle_ghost(id: String) -> void:
	if edit_id != "" or id == "":
		return
	ghost_id = "" if ghost_id == id else id
	if ghost_id == "":
		_toast("已收起参照")
	else:
		_toast("参照「%s」（%s）· 照着描一笔，回车录入 · E 精修控制点" % [
			_label(id), "已改" if SpellMatch.is_custom(id) else "出厂形"])
	_refresh(true)

## 技能显示名，取「·」前那一截当短名。
func _label(id: String) -> String:
	for s in skills:
		if String(s.id) == id:
			return String(s.name).split("·")[0]
	return id

## 回车：把手绘的这一笔录成参照字的新笔形，落盘并立即在战局生效。
func _learn_fixed() -> void:
	if edit_id != "":
		return
	if ghost_id == "":
		_toast("先按 1/2 选一个固定笔形")
		return
	var model := _to_model(active_path())
	if model.size() < 2:
		_toast("先画一笔再录入")
		return
	SpellMatch.set_custom(ghost_id, model)
	var err := SpellMatch.save_custom()
	_rebind_fixed(ghost_id)
	_toast("已把当前笔录入「%s」并落盘，下次开局仍是这个形%s" % [
		_label(ghost_id), "" if err == OK else "（写盘失败 %d）" % err])
	_refresh(true)

## R（非编辑态）：把固定笔形全退回出厂形，并清掉台内 3~8 的试录。
## 战局里玩家自己绑的 3~8 不动 —— 那是战局资产，不该被调试台顺手抹掉。
func _restore_all() -> void:
	if not reset_armed:
		reset_armed = true
		_toast("再按一次 R：把固定笔形恢复出厂形，并清空台内试录")
		return
	reset_armed = false
	var ids := SpellMatch.ancient_ids()
	for id in ids:
		SpellMatch.set_custom(String(id), PackedVector2Array())
	var err := SpellMatch.save_custom()
	_load_skills()
	for id in ids:
		_rebind_fixed(String(id))
	_toast("已全部恢复默认%s" % ("" if err == OK else "（写盘失败 %d）" % err))
	_refresh(true)

## 把当前笔形录进第 idx 个技能（仅调试台内生效，不动战局）。
func _learn(idx: int) -> void:
	if idx < 0 or idx >= skills.size():
		return
	var f := SpellMatch.feature(active_path())
	if f.is_empty():
		_toast("没有可用笔画")
		return
	var s: Dictionary = skills[idx]
	s.cloud = f.cloud
	s.bound = true
	_toast("已把当前笔形录入「%s」" % String(s.name))
	_refresh(true)

func _toast(msg: String) -> void:
	toast_text = msg
	toast_t = 1.6

func active_path() -> PackedVector2Array:
	if edit_id != "":
		return edit_pts       # 编辑中：右侧匹配栏直接给编辑形的实时得分
	if cur.size() >= 2:
		return cur
	if not strokes.is_empty():
		return strokes[strokes.size() - 1]
	return PackedVector2Array()

func tv_max() -> float:
	return game.tv_max() if game != null else Game.TV_MAX_BASE

func elapsed() -> float:
	return draw_t if drawing else last_t

# ============================== 绘制 ==============================

## 描摹底：把参照字当前生效的笔形淡铺在画布上，起点标个圈提示下笔处。
func _paint_ghost(c: Control) -> void:
	if ghost_id == "":
		return
	var pts := _map_to_pad(SpellMatch.ancient_stroke(ghost_id))
	if pts.size() < 2:
		return
	for i in pts.size() - 1:
		c.draw_line(pts[i], pts[i + 1], Color(RED.r, RED.g, RED.b, 0.20), 16.0)
	c.draw_circle(pts[0], 9.0, Color(RED.r, RED.g, RED.b, 0.32))

## 编辑模式：墨迹形 + 带序号的控制点 + 段中把手。
func _paint_edit(c: Control) -> void:
	if edit_pts.size() < 2:
		_t(c, Vector2(20, 20), "点太少", 14, RED)
		return
	InkRenderer.draw_brush_path(c, _dense(edit_pts), 0.9, false)
	for i in edit_pts.size() - 1:
		var m := edit_pts[i].lerp(edit_pts[i + 1], 0.5)
		c.draw_circle(m, 4.5, Color(GREY.r, GREY.g, GREY.b, 0.5))
	for i in edit_pts.size():
		var p := edit_pts[i]
		var hot := i == drag_i
		c.draw_circle(p, 9.0 if hot else 7.0, RED if hot else Color(RED.r, RED.g, RED.b, 0.75))
		c.draw_circle(p, 3.0, PAPER)
		c.draw_string(font, p + Vector2(10, -6), str(i + 1),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, INK)

## 控制点之间补密，让 InkRenderer 的笔锋插值有料可用。
func _dense(ctrl: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array([ctrl[0]])
	for i in range(1, ctrl.size()):
		var n: int = maxi(int(ctrl[i - 1].distance_to(ctrl[i]) / 8.0), 1)
		for k in range(1, n + 1):
			out.append(ctrl[i - 1].lerp(ctrl[i], float(k) / float(n)))
	return out

func _paint(c: Control) -> void:
	c.draw_rect(Rect2(Vector2.ZERO, c.size), DIM)
	c.draw_rect(Rect2(PANEL_X - 8.0, 8.0, PANEL_W, c.size.y - 16.0),
		Color(0.96, 0.945, 0.91, 0.97))
	var head := "神纹调试台 · 左键书写 · 1/2 选古代神纹 → 回车录入并落盘 · E 精修 · C 清空 · R 全部恢复默认 · F2 关闭"
	if edit_id != "":
		head = "精修「%s」%s · 拖点改形 · 点灰把手插点 · 右键删点 · S 保存 · R 出厂 · Esc 退出" % [
			_label(edit_id), "（未保存）" if dirty else ""]
	_t(c, Vector2(16, 16), head, 16, Color(0.9, 0.87, 0.82))
	var y := _paint_cost(c, feat)
	_paint_match(c, y)
	if toast_t > 0.0:
		_t(c, Vector2(PANEL_X, c.size.y - 30.0), toast_text, 14,
			Color(RED.r, RED.g, RED.b, clampf(toast_t / 1.4, 0.0, 1.0)))

## 编辑态的右栏抬头：控制点数、来源、以及最要命的「和别的字有多像」。
func _paint_edit_info(c: Control, x: float, y0: float) -> float:
	var y := y0
	_t(c, Vector2(x, y), "笔形精修：%s" % _label(edit_id), 17, INK)
	y += 28.0
	_row(c, x, y, "控制点", "%d 个" % edit_pts.size(), INK)
	y += ROW_H
	_row(c, x, y, "来源", "已改（%s）" % ("未存盘" if dirty else "已存盘")
		if SpellMatch.is_custom(edit_id) or dirty else "出厂形", RED if dirty else INK)
	y += ROW_H
	var rival := _rival_score()
	_row(c, x, y, "与他字最像", "%.0f%%（门槛 %.0f%%）" % [
		rival * 100.0, SpellMatch.SCORE_MIN * 100.0],
		RED if rival >= SpellMatch.SCORE_MIN - 0.08 else INK)
	y += ROW_H + 4.0
	if rival >= SpellMatch.SCORE_MIN - 0.08:
		_t(c, Vector2(x, y), "太像别的字了：实战会互相误触，把差异拉开", 13,
			Color(RED.r, RED.g, RED.b, 0.9))
	y += 26.0
	return y

## 编辑中的形和「其他已绑技能」的最高相似度 —— 越低越安全。
func _rival_score() -> float:
	var best := 0.0
	for r in rows:
		var s: Dictionary = r.s
		if String(s.id) == edit_id or not bool(s.bound):
			continue
		best = maxf(best, float(r.c.sim))
	return best

func _paint_cost(c: Control, feat: Dictionary) -> float:
	var x := PANEL_X
	var y := 22.0
	if edit_id != "":
		return _paint_edit_info(c, x, y)
	_t(c, Vector2(x, y), "本笔消耗", 17, INK)
	y += 28.0
	var px := float(feat.get("px", 0.0))
	var ink_cost := px * Game.TV_COST_PER_PX
	var t := elapsed()
	var drain := Game.BULLET_TV_DRAIN * t
	var total := ink_cost + drain
	var cap := tv_max()
	var left := cap - total
	_row(c, x, y, "笔画长度", "%.0f px" % px, INK)
	y += ROW_H
	_row(c, x, y, "笔墨消耗", "%.0f 时（%.0f px × %.1f）" % [ink_cost, px, Game.TV_COST_PER_PX], INK)
	y += ROW_H
	_row(c, x, y, "书写耗时", "%.2f s → 子弹流逝 %.0f 时" % [t, drain], INK)
	y += ROW_H
	_row(c, x, y, "合计消耗", "%.0f 时" % total, RED if total > cap else INK)
	y += ROW_H
	_row(c, x, y, "写完余额", "%.0f / %.0f 时" % [maxf(left, 0.0), cap],
		RED if left < 120.0 else INK)
	y += ROW_H + 4.0
	# 消耗条：墨耗 + 流逝 占满 TV 上限的比例
	var bw := PANEL_W - 24.0
	var bx := x
	c.draw_rect(Rect2(bx, y, bw, 12.0), Color(0, 0, 0, 0.08))
	var f1: float = clampf(ink_cost / cap, 0.0, 1.0)
	var f2: float = clampf(total / cap, 0.0, 1.0)
	c.draw_rect(Rect2(bx, y, bw * f2, 12.0), Color(GREY.r, GREY.g, GREY.b, 0.45))
	c.draw_rect(Rect2(bx, y, bw * f1, 12.0), INK)
	var thr := bx + bw * Game.BIND_ENERGY_RATIO
	c.draw_line(Vector2(thr, y - 3.0), Vector2(thr, y + 15.0), Color(RED.r, RED.g, RED.b, 0.7), 1.5)
	y += 20.0
	var warn := ""
	if total >= cap:
		warn = "墨尽：笔尖干涸，实战中这一笔会被截断"
	elif total >= cap * Game.BIND_ENERGY_RATIO:
		warn = "过觉醒线 %.0f 时（满墨起笔的 %.0f%%，含子弹流逝）：没命中已有神纹时，有 %.0f%% 概率点亮空碑" % [
			cap * Game.BIND_ENERGY_RATIO, Game.BIND_ENERGY_RATIO * 100.0,
			Game.BIND_CHANCE * 100.0]
	elif px < SpellMatch.MIN_LEN:
		warn = "笔画短于 %.0f px：不参与神纹判定，只出斩击" % SpellMatch.MIN_LEN
	if warn != "":
		_t(c, Vector2(x, y), warn, 13, Color(RED.r, RED.g, RED.b, 0.9))
	y += 26.0
	return y

func _paint_match(c: Control, y0: float) -> void:
	var x := PANEL_X
	var y := y0
	_t(c, Vector2(x, y), "$Q 匹配度（得分 ≥%.0f%% · 笔长 ≥%.0f · 点云比对，写法与笔序无关）" % [
		SpellMatch.SCORE_MIN * 100.0, SpellMatch.MIN_LEN], 14, INK)
	y += 26.0
	for r in rows:
		var s: Dictionary = r.s
		var chk: Dictionary = r.c
		var sim := float(chk.sim)
		var ok := bool(chk.ok)
		var name_col := RED if ok else GREY
		var idx := int(r.i)
		var tag := ""
		if bool(s.ancient):
			if String(s.id) == ghost_id:
				tag = "  ◀ 参照中 · 回车录入"
			elif SpellMatch.is_custom(String(s.id)):
				tag = "  [已改]"
		elif not bool(s.bound):
			tag = "  [按 %d 录入]" % (idx + 1)
		_t(c, Vector2(x, y), "%s%s" % [String(s.name), tag], 15, name_col)
		var pct: float = clampf(sim, 0.0, 1.0) if sim > -2.0 else 0.0
		var bw := 150.0
		var bx := x + 150.0
		c.draw_rect(Rect2(bx, y + 4.0, bw, 10.0), Color(0, 0, 0, 0.08))
		var bar_col := RED if bool(chk.sim_ok) else Color(GREY.r, GREY.g, GREY.b, 0.55)
		c.draw_rect(Rect2(bx, y + 4.0, bw * pct, 10.0), bar_col)
		var gate := bx + bw * SpellMatch.SCORE_MIN
		c.draw_line(Vector2(gate, y + 1.0), Vector2(gate, y + 17.0), Color(0, 0, 0, 0.45), 1.0)
		var simtxt := "--" if sim <= -2.0 else "%.0f%%" % (sim * 100.0)
		_t(c, Vector2(bx + bw + 8.0, y), simtxt, 14, INK if bool(chk.sim_ok) else GREY)
		var note := String(chk.reason)
		if ok:
			note = "命中 · 冷却 %.0fs（释放不耗时间之力）" % float(s.cd)
		_t(c, Vector2(x + 6.0, y + 17.0), note, 12,
			Color(RED.r, RED.g, RED.b, 0.85) if ok else Color(GREY.r, GREY.g, GREY.b, 0.8))
		y += MATCH_H

func _row(c: Control, x: float, y: float, k: String, v: String, col: Color) -> void:
	_t(c, Vector2(x, y), k, 14, GREY)
	_t(c, Vector2(x + 96.0, y), v, 14, col)

func _t(c: Control, pos: Vector2, s: String, size: int, col: Color) -> void:
	c.draw_string(font, Vector2(pos.x, pos.y + size), s,
		HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)

func _on_close() -> void:
	closed.emit()
	queue_free()
