class_name InkEditor
extends CanvasLayer
## 墨笔编辑器：左侧试笔画布 + 右侧参数面板，实时预览 InkStyle.current。
## 保存写入 user://ink_style.tres（编辑器内同时写 res://ink_style.tres 成为默认预设）。
## F1 / Esc 关闭（恢复游戏）。

signal closed

const PANEL_X := 768.0
const PANEL_W := 372.0
const ROW_H := 22.0
const INK := Color("#1A1714")
const GREY := Color("#4A443C")

const ROWS := [
	{"p": "width_start", "t": "起笔宽", "min": 2.0, "max": 40.0, "st": 0.5},
	{"p": "width_end", "t": "收锋宽", "min": 0.5, "max": 10.0, "st": 0.1},
	{"p": "width_taper", "t": "衰减指数", "min": 0.2, "max": 2.5, "st": 0.05},
	{"p": "width_wobble_amp", "t": "墨量波动", "min": 0.0, "max": 3.0, "st": 0.05},
	{"p": "width_wobble_freq", "t": "波动频率", "min": 4.0, "max": 60.0, "st": 1.0},
	{"p": "body_alpha", "t": "墨浓", "min": 0.2, "max": 1.0, "st": 0.02},
	{"p": "halo_scale", "t": "晕边宽度", "min": 1.0, "max": 3.0, "st": 0.05},
	{"p": "halo_alpha", "t": "晕边浓淡", "min": 0.0, "max": 0.5, "st": 0.01},
	{"p": "edge_jitter", "t": "轮廓毛糙", "min": 0.0, "max": 0.5, "st": 0.01},
	{"p": "smooth_iters", "t": "平滑迭代", "min": 0.0, "max": 4.0, "st": 1.0},
	{"p": "feibai_chance", "t": "飞白密度", "min": 0.0, "max": 1.0, "st": 0.02},
	{"p": "feibai_alpha", "t": "飞白强度", "min": 0.0, "max": 0.6, "st": 0.01},
	{"p": "splatter_chance", "t": "溅墨密度", "min": 0.0, "max": 1.0, "st": 0.02},
	{"p": "splatter_alpha", "t": "溅墨浓淡", "min": 0.0, "max": 1.0, "st": 0.02},
	{"p": "splatter_size_max", "t": "溅墨大小", "min": 1.0, "max": 6.0, "st": 0.1},
	{"p": "tail_strands", "t": "收锋丝数", "min": 0.0, "max": 12.0, "st": 1.0},
	{"p": "tail_spread", "t": "收锋张角", "min": 0.0, "max": 1.5, "st": 0.05},
	{"p": "tail_len_max", "t": "收锋长度", "min": 0.0, "max": 60.0, "st": 1.0},
	{"p": "bleed_enabled", "t": "渗墨开关", "min": 0.0, "max": 1.0, "st": 1.0},
	{"p": "bleed_radius", "t": "渗墨速度", "min": 0.0, "max": 3.0, "st": 0.05},
	{"p": "bleed_fade", "t": "墨迹消褪", "min": 0.90, "max": 1.0, "st": 0.001},
	{"p": "grain_strength", "t": "纸颗粒", "min": 0.0, "max": 1.0, "st": 0.02},
]

var strokes: Array[PackedVector2Array] = []
var cur := PackedVector2Array()
var drawing := false
var toast_t := 0.0
var toast_text := ""
var font: SystemFont
var board: Control
var pad: Control
var _sliders := {}
var _val_labels := {}

class _Board extends Control:
	var ed: InkEditor
	func _draw() -> void:
		if ed == null:
			return
		# 全屏压暗 + 面板底
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.045, 0.04, 0.85))
		draw_rect(Rect2(InkEditor.PANEL_X - 8, 8, InkEditor.PANEL_W, size.y - 16),
			Color(0.96, 0.945, 0.91, 0.97))
		var f := ed.font
		if f != null:
			draw_string(f, Vector2(16, 32), "墨笔编辑器 · 左侧按住左键试笔 · F1/Esc 关闭",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(0.9, 0.87, 0.82))
			draw_string(f, Vector2(InkEditor.PANEL_X + 8, 34), "笔触参数",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 16, InkEditor.GREY)
			if ed.toast_t > 0.0:
				draw_string(f, Vector2(InkEditor.PANEL_X + 8, size.y - 26), ed.toast_text,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
					Color(0.75, 0.22, 0.17, clampf(ed.toast_t / 1.4, 0.0, 1.0)))

class _Pad extends Control:
	var ed: InkEditor
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		clip_contents = true
	func _gui_input(event: InputEvent) -> void:
		if ed == null:
			return
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				ed.drawing = true
				ed.cur = PackedVector2Array([_clamped(get_local_mouse_position())])
			else:
				if ed.drawing and ed.cur.size() >= 2:
					ed.strokes.append(ed.cur)
					if ed.strokes.size() > 24:
						ed.strokes.remove_at(0)
				ed.drawing = false
				ed.cur = PackedVector2Array()
			queue_redraw()
	func _process(_delta: float) -> void:
		if ed != null and ed.drawing:
			var p := _clamped(get_local_mouse_position())
			var last: Vector2 = ed.cur[ed.cur.size() - 1]
			if p.distance_to(last) >= 6.0:
				ed.cur.append(p)
				queue_redraw()
	func _draw() -> void:
		var s := InkStyle.current
		var paper: Color = s.paper_color if s != null else Color("#F5F1E8")
		draw_rect(Rect2(Vector2.ZERO, size), paper)
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.3), false, 1.0)
		if ed == null:
			return
		for st in ed.strokes:
			InkRenderer.draw_brush_path(self, st, 0.95, false)
		if ed.cur.size() >= 2:
			InkRenderer.draw_brush_path(self, ed.cur, 0.95, false)
	func _clamped(p: Vector2) -> Vector2:
		return Vector2(clampf(p.x, 4.0, size.x - 4.0), clampf(p.y, 4.0, size.y - 4.0))

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	font = SystemFont.new()
	font.font_names = PackedStringArray([
		"Microsoft YaHei UI", "Microsoft YaHei", "SimHei", "Noto Sans CJK SC"])
	board = _Board.new()
	board.ed = self
	board.position = Vector2.ZERO
	board.size = Vector2(1152, 648)
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(board)
	pad = _Pad.new()
	pad.ed = self
	pad.position = Vector2(12, 46)
	pad.size = Vector2(744, 590)
	board.add_child(pad)
	_build_panel()
	InkStyle.style_changed.connect(_on_style_changed)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode in [KEY_F1, KEY_F10, KEY_ESCAPE]:
		_on_close()
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if toast_t > 0.0:
		toast_t -= delta
		if toast_t <= 0.0:
			board.queue_redraw()

func _build_panel() -> void:
	var y := 44.0
	for row in ROWS:
		var prop: String = row.p
		var lb := _mk_label(String(row.t), Vector2(PANEL_X + 4, y + 4), 13, GREY)
		lb.custom_minimum_size = Vector2(78, ROW_H)
		var sl := HSlider.new()
		sl.min_value = float(row.min)
		sl.max_value = float(row.max)
		sl.step = float(row.st)
		sl.position = Vector2(PANEL_X + 88, y + 4)
		sl.size = Vector2(176, 18)
		sl.value = float(InkStyle.current.get(prop))
		sl.value_changed.connect(_on_slider.bind(prop))
		board.add_child(sl)
		_sliders[prop] = sl
		var vl := _mk_label(_fmt(sl.value), Vector2(PANEL_X + 272, y + 4), 12, INK)
		_val_labels[prop] = vl
		y += ROW_H
	y += 6.0
	# 色块
	var cb1 := ColorPickerButton.new()
	cb1.text = "墨色"
	cb1.color = InkStyle.current.ink_color
	cb1.position = Vector2(PANEL_X + 8, y)
	cb1.custom_minimum_size = Vector2(110, 28)
	cb1.color_changed.connect(func(c: Color) -> void: _apply_param(&"ink_color", c))
	board.add_child(cb1)
	_sliders["ink_color"] = cb1
	var cb2 := ColorPickerButton.new()
	cb2.text = "纸色"
	cb2.color = InkStyle.current.paper_color
	cb2.position = Vector2(PANEL_X + 126, y)
	cb2.custom_minimum_size = Vector2(110, 28)
	cb2.color_changed.connect(func(c: Color) -> void: _apply_param(&"paper_color", c))
	board.add_child(cb2)
	_sliders["paper_color"] = cb2
	y += 38.0
	# 按钮 2x2
	_mk_btn("清空试笔", Vector2(PANEL_X + 8, y), _on_clear)
	_mk_btn("重置默认", Vector2(PANEL_X + 190, y), _on_reset)
	y += 36.0
	_mk_btn("保存并应用", Vector2(PANEL_X + 8, y), _on_save)
	_mk_btn("关闭（F1）", Vector2(PANEL_X + 190, y), _on_close)

func _mk_label(text: String, pos: Vector2, size: int, col: Color) -> Label:
	var lb := Label.new()
	lb.text = text
	lb.position = pos
	lb.add_theme_font_override("font", font)
	lb.add_theme_font_size_override("font_size", size)
	lb.add_theme_color_override("font_color", col)
	board.add_child(lb)
	return lb

func _mk_btn(text: String, pos: Vector2, fn: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.custom_minimum_size = Vector2(172, 30)
	b.add_theme_font_override("font", font)
	b.add_theme_font_size_override("font_size", 14)
	b.pressed.connect(fn)
	board.add_child(b)

func _on_slider(value: float, prop: String) -> void:
	_apply_param(StringName(prop), value)
	var vl: Label = _val_labels.get(prop)
	if vl != null:
		vl.text = _fmt(value)

func _apply_param(prop: StringName, value: Variant) -> void:
	InkStyle.set_param(prop, value)
	pad.queue_redraw()

func _on_style_changed() -> void:
	pad.queue_redraw()
	board.queue_redraw()

func _on_clear() -> void:
	strokes.clear()
	cur = PackedVector2Array()
	pad.queue_redraw()

func _on_reset() -> void:
	InkStyle.reset_default()
	for row in ROWS:
		var prop: String = row.p
		var sl: HSlider = _sliders[prop]
		sl.set_value_no_signal(float(InkStyle.current.get(prop)))
		(_val_labels[prop] as Label).text = _fmt(sl.value)
	(_sliders["ink_color"] as ColorPickerButton).color = InkStyle.current.ink_color	(_sliders["paper_color"] as ColorPickerButton).color = InkStyle.current.paper_color
	_toast("已重置默认")

func _on_save() -> void:
	var e1 := InkStyle.save_user()
	var msg := ""
	if e1 == OK:
		msg = "已保存 user://ink_style.tres"
	else:
		msg = "保存失败 err=%d" % e1
	if OS.has_feature("editor"):
		var e2 := InkStyle.save_res()
		if e2 == OK:
			msg += " + res://ink_style.tres"
	_toast(msg)

func _on_close() -> void:
	get_tree().paused = false
	closed.emit()
	queue_free()

func _toast(text: String) -> void:
	toast_text = text
	toast_t = 1.4
	board.queue_redraw()

static func _fmt(v: float) -> String:
	if absf(v - roundf(v)) < 0.0005 and absf(v) < 100.0:
		return str(int(roundf(v)))
	if absf(v) <= 1.0:
		return "%.3f" % v
	return "%.2f" % v
