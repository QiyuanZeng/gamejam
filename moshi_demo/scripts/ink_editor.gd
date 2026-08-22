class_name InkEditor
extends CanvasLayer
## 水笔编辑器：左侧试笔水面 + 右侧参数面板，实时预览水流笔触（WaterRenderer）。
## 「保存并应用」写 user://water_style.json 并推入 WaterRenderer.current —— 局内划线与地面拓印随即改观。
## F1 / Esc 关闭（恢复游戏）。

signal closed

const PANEL_X := 768.0
const PANEL_W := 372.0
const ROW_H := 17.0
const INK := Color("#1A1714")
const GREY := Color("#4A443C")
const SAVE_PATH := WaterRenderer.SAVE_PATH

const ROWS := [
	{"p": "cut_width", "t": "切痕宽", "min": 0.5, "max": 10.0, "st": 0.1},
	{"p": "cut_alpha", "t": "切痕亮度", "min": 0.0, "max": 1.0, "st": 0.02},
	{"p": "cut_life", "t": "切痕寿命", "min": 0.05, "max": 2.0, "st": 0.05},
	{"p": "head_soft", "t": "端点柔化", "min": 0.02, "max": 0.9, "st": 0.02},
	{"p": "width_start", "t": "入水宽", "min": 1.0, "max": 40.0, "st": 0.5},
	{"p": "width_end", "t": "尾流宽", "min": 0.5, "max": 20.0, "st": 0.1},
	{"p": "width_taper", "t": "衰减指数", "min": 0.2, "max": 2.5, "st": 0.05},
	{"p": "spread_speed", "t": "扩散速度", "min": 0.0, "max": 120.0, "st": 1.0},
	{"p": "body_alpha", "t": "水体浓淡", "min": 0.0, "max": 1.0, "st": 0.02},
	{"p": "halo_scale", "t": "外扰宽度", "min": 1.0, "max": 3.5, "st": 0.05},
	{"p": "halo_alpha", "t": "外扰浓淡", "min": 0.0, "max": 0.6, "st": 0.01},
	{"p": "edge_jitter", "t": "水边毛糙", "min": 0.0, "max": 0.6, "st": 0.01},
	{"p": "wobble_amp", "t": "水面扰动", "min": 0.0, "max": 4.0, "st": 0.05},
	{"p": "wobble_freq", "t": "扰动频率", "min": 2.0, "max": 60.0, "st": 1.0},
	{"p": "smooth_iters", "t": "平滑迭代", "min": 0.0, "max": 4.0, "st": 1.0},
	{"p": "print_step", "t": "脚印间隔", "min": 4.0, "max": 40.0, "st": 1.0},
	{"p": "print_size", "t": "脚印大小", "min": 0.0, "max": 24.0, "st": 0.5},
	{"p": "print_stagger", "t": "脚印错距", "min": 0.0, "max": 30.0, "st": 0.5},
	{"p": "print_alpha", "t": "脚印浓淡", "min": 0.0, "max": 1.0, "st": 0.02},
	{"p": "print_squash", "t": "脚印压扁", "min": 0.15, "max": 1.0, "st": 0.02},
	{"p": "print_life", "t": "脚印寿命", "min": 0.2, "max": 8.0, "st": 0.1},
	{"p": "print_ring", "t": "脚印外圈", "min": 0.0, "max": 1.0, "st": 0.02},
	{"p": "wake_angle", "t": "V波张角", "min": 0.0, "max": 1.2, "st": 0.02},
	{"p": "wake_speed", "t": "V波速度", "min": 0.0, "max": 200.0, "st": 2.0},
	{"p": "wake_alpha", "t": "V波亮度", "min": 0.0, "max": 1.0, "st": 0.02},
	{"p": "wake_crest", "t": "V波线宽", "min": 0.5, "max": 6.0, "st": 0.1},
	{"p": "wake_arms", "t": "V波层数", "min": 0.0, "max": 4.0, "st": 1.0},
	{"p": "caustic_chance", "t": "焦散密度", "min": 0.0, "max": 1.0, "st": 0.02},
	{"p": "caustic_alpha", "t": "焦散亮度", "min": 0.0, "max": 1.0, "st": 0.02},
	{"p": "caustic_len_max", "t": "焦散长度", "min": 2.0, "max": 60.0, "st": 1.0},
	{"p": "foam_chance", "t": "泡沫密度", "min": 0.0, "max": 1.0, "st": 0.02},
	{"p": "foam_alpha", "t": "泡沫浓淡", "min": 0.0, "max": 1.0, "st": 0.02},
	{"p": "foam_size_max", "t": "泡沫大小", "min": 0.5, "max": 8.0, "st": 0.1},
	{"p": "foam_spread", "t": "泡沫散布", "min": 0.0, "max": 40.0, "st": 0.5},
	{"p": "foam_step", "t": "泡沫间隔", "min": 1.0, "max": 8.0, "st": 1.0},
	{"p": "ripple_step", "t": "涟漪间隔", "min": 4.0, "max": 48.0, "st": 1.0},
	{"p": "ripple_radius", "t": "涟漪初径", "min": 1.0, "max": 60.0, "st": 1.0},
	{"p": "ripple_speed", "t": "涟漪扩速", "min": 0.0, "max": 160.0, "st": 2.0},
	{"p": "ripple_alpha", "t": "涟漪浓淡", "min": 0.0, "max": 1.0, "st": 0.02},
	{"p": "life_time", "t": "尾迹寿命", "min": 0.3, "max": 10.0, "st": 0.1},
	{"p": "fade_curve", "t": "消散曲线", "min": 0.3, "max": 4.0, "st": 0.05},
]

const COLOR_ROWS := [
	{"p": "water_color", "t": "水色"},
	{"p": "foam_color", "t": "泡沫色"},
	{"p": "surface_color", "t": "水面色"},
]

var params := {}

var strokes: Array = []
var cur := PackedVector2Array()
var cur_ages := PackedFloat32Array()
var drawing := false
var surface_phase := 0.0
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
			draw_string(f, Vector2(16, 32), "水笔编辑器 · 左侧按住左键试笔 · F1/Esc 关闭",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(0.9, 0.87, 0.82))
			draw_string(f, Vector2(InkEditor.PANEL_X + 8, 34), "水流参数",
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
				ed.cur_ages = PackedFloat32Array([0.0])
			else:
				if ed.drawing and ed.cur.size() >= 2:
					ed.strokes.append({"pts": ed.cur, "ages": ed.cur_ages})
					if ed.strokes.size() > 24:
						ed.strokes.remove_at(0)
				ed.drawing = false
				ed.cur = PackedVector2Array()
				ed.cur_ages = PackedFloat32Array()
			queue_redraw()

	func _process(delta: float) -> void:
		if ed == null:
			return
		# 年龄推进：所有已存在采样点变老；正在画的笔画同步计龄
		var life: float = WaterRenderer.getf(ed.params, "life_time")
		for i in range(ed.strokes.size() - 1, -1, -1):
			var s: Dictionary = ed.strokes[i]
			var ages: PackedFloat32Array = s.ages
			for k in ages.size():
				ages[k] += delta
			# 最年轻的点也超寿命 → 整条已消失，回收
			if ages.size() > 0 and ages[ages.size() - 1] > life:
				ed.strokes.remove_at(i)
		for k in ed.cur_ages.size():
			ed.cur_ages[k] += delta
		if ed.drawing:
			var p := _clamped(get_local_mouse_position())
			var last: Vector2 = ed.cur[ed.cur.size() - 1]
			if p.distance_to(last) >= 6.0:
				ed.cur.append(p)
				ed.cur_ages.append(0.0)
		queue_redraw()

	func _draw() -> void:
		if ed == null:
			draw_rect(Rect2(Vector2.ZERO, size), WaterRenderer.DEFAULTS.surface_color)
			return
		WaterRenderer.draw_water_surface(self, Rect2(Vector2.ZERO, size),
			ed.params, ed.surface_phase)
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.18), false, 1.0)
		for s in ed.strokes:
			WaterRenderer.draw_water_path(self, s.pts, s.ages, 1.0, ed.params)
		if ed.cur.size() >= 2:
			WaterRenderer.draw_water_path(self, ed.cur, ed.cur_ages, 1.0, ed.params)
	func _clamped(p: Vector2) -> Vector2:
		return Vector2(clampf(p.x, 4.0, size.x - 4.0), clampf(p.y, 4.0, size.y - 4.0))

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	params = _load_params()
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
	# 武装门：开启键松开（或 0.25s 兜底）后才接受关闭键，防同事件秒关
	get_tree().create_timer(0.25).timeout.connect(_arm)

func _load_params() -> Dictionary:
	WaterRenderer.ensure_loaded()
	return WaterRenderer.current.duplicate(true)

func _save_params() -> Error:
	return WaterRenderer.save_to_disk(params)

var _armed := false

func _arm() -> void:
	_armed = true

func _input(event: InputEvent) -> void:
	if not _armed:
		if event is InputEventKey and not event.pressed \
			and event.keycode in [KEY_F1, KEY_F10, KEY_ESCAPE]:
			_armed = true
		return
	if event is InputEventKey and event.pressed and event.keycode in [KEY_F1, KEY_F10, KEY_ESCAPE]:
		_on_close()
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	surface_phase += delta
	if toast_t > 0.0:
		toast_t -= delta
		if toast_t <= 0.0:
			board.queue_redraw()

func _build_panel() -> void:
	# 两列布局：参数多，单列会溢出视口
	var col_w := 186.0
	var rows_per_col := int(ceil(float(ROWS.size()) / 2.0))
	var top := 44.0
	var y := top
	var col_x := PANEL_X + 4
	for ri in ROWS.size():
		if ri == rows_per_col:
			y = top
			col_x = PANEL_X + 4 + col_w
		var row: Dictionary = ROWS[ri]
		var prop: String = row.p
		var lb := _mk_label(String(row.t), Vector2(col_x, y), 11, GREY)
		lb.custom_minimum_size = Vector2(62, ROW_H)
		var sl := HSlider.new()
		sl.min_value = float(row.min)
		sl.max_value = float(row.max)
		sl.step = float(row.st)
		sl.position = Vector2(col_x + 64, y + 1)
		sl.size = Vector2(80, 15)
		sl.value = float(params[prop])
		sl.value_changed.connect(_on_slider.bind(prop))
		board.add_child(sl)
		_sliders[prop] = sl
		var vl := _mk_label(_fmt(sl.value), Vector2(col_x + 148, y), 11, INK)
		_val_labels[prop] = vl
		y += ROW_H
	y = top + float(rows_per_col) * ROW_H + 8.0
	# 色块
	var cx := PANEL_X + 8
	for crow in COLOR_ROWS:
		var cprop: String = crow.p
		var cb := ColorPickerButton.new()
		cb.text = String(crow.t)
		cb.color = params[cprop]
		cb.position = Vector2(cx, y)
		cb.custom_minimum_size = Vector2(112, 26)
		cb.color_changed.connect(func(c: Color) -> void: _apply_param(StringName(cprop), c))
		board.add_child(cb)
		_sliders[cprop] = cb
		cx += 118.0
	y += 34.0
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
	params[String(prop)] = value
	pad.queue_redraw()
	board.queue_redraw()

func _on_clear() -> void:
	strokes.clear()
	cur = PackedVector2Array()
	cur_ages = PackedFloat32Array()
	pad.queue_redraw()

func _on_reset() -> void:
	params = WaterRenderer.DEFAULTS.duplicate(true)
	for row in ROWS:
		var prop: String = row.p
		var sl: HSlider = _sliders[prop]
		sl.set_value_no_signal(float(params[prop]))
		(_val_labels[prop] as Label).text = _fmt(sl.value)
	for crow in COLOR_ROWS:
		(_sliders[crow.p] as ColorPickerButton).color = params[crow.p]
	pad.queue_redraw()
	_toast("已重置默认")

func _on_save() -> void:
	var e := _save_params()
	WaterRenderer.set_current(params)
	_toast("已保存并应用 " + SAVE_PATH if e == OK else "保存失败 err=%d" % e)

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
