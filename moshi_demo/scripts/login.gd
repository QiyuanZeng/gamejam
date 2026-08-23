extends Control
## 登录页（标题屏）「时之回环」。
## UI 文字烧在背景整图里，本脚本只叠：背景 5 态轮播、菜单透明热区、金色光标+下划线高亮、设置弹窗。

const BG_PATHS := [
	"res://assets/art/login/1.png",
	"res://assets/art/login/2.png",
	"res://assets/art/login/3.png",
	"res://assets/art/login/4.png",
	"res://assets/art/login/5.png",
]
const VIDEO_PATH := "res://assets/start.ogv"
const CAROUSEL_INTERVAL := 8.0
const FADE_TIME := 1.0
const GOLD := Color("#E8C36A")
const GAME_FONT := preload("res://assets/fonts/MFYueYuan_Noncommercial-Regular.ttf")

## 菜单热区（与设计稿对齐：中心/尺寸为视口百分比）
const MENU_ITEMS := [
	{"label": "开始游戏", "x": 0.140, "y": 0.490, "w": 0.14, "h": 0.055},
	{"label": "继续", "x": 0.115, "y": 0.570, "w": 0.10, "h": 0.050},
	{"label": "设置", "x": 0.115, "y": 0.645, "w": 0.10, "h": 0.050},
	{"label": "退出", "x": 0.115, "y": 0.720, "w": 0.10, "h": 0.050},
]

var bg_current: TextureRect
var bg_next: TextureRect
var bg_video: VideoStreamPlayer
var bg_index := 0
var buttons: Array[Button] = []

var cursor: Polygon2D
var underline: ColorRect
var toast: Label
var settings_popup: CanvasLayer
var busy := false

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	add_theme_font_override("font", GAME_FONT)
	_build_background()
	_build_menu()
	_build_toast()
	_build_settings()
	if bg_video == null:
		_carousel_loop()
	buttons[0].grab_focus()

func _build_background() -> void:
	if ResourceLoader.exists(VIDEO_PATH):
		bg_video = VideoStreamPlayer.new()
		bg_video.stream = load(VIDEO_PATH)
		bg_video.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg_video.expand = true
		bg_video.loop = true
		bg_video.autoplay = true
		bg_video.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg_video.finished.connect(bg_video.play)
		add_child(bg_video)
		bg_video.play()
		return
	for tex_path in BG_PATHS:
		if not ResourceLoader.exists(tex_path):
			push_error("登录页背景缺失: " + tex_path)
	bg_current = TextureRect.new()
	bg_next = TextureRect.new()
	for tr: TextureRect in [bg_current, bg_next]:
		tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(tr)
	bg_next.modulate.a = 0.0
	bg_current.texture = load(BG_PATHS[0])

func _build_menu() -> void:
	cursor = Polygon2D.new()
	cursor.color = GOLD
	cursor.polygon = _star_points(1.0)
	add_child(cursor)
	underline = ColorRect.new()
	underline.color = Color(GOLD.r, GOLD.g, GOLD.b, 0.85)
	add_child(underline)
	for i in MENU_ITEMS.size():
		var item: Dictionary = MENU_ITEMS[i]
		var btn := Button.new()
		btn.flat = true
		btn.text = ""
		btn.focus_mode = Control.FOCUS_ALL
		var fb := StyleBoxFlat.new()
		fb.bg_color = Color(0, 0, 0, 0)
		for state in ["normal", "hover", "focused", "pressed", "disabled"]:
			btn.add_theme_stylebox_override(state, fb)
		btn.set_anchors_preset(Control.PRESET_FULL_RECT)
		btn.anchor_left = item.x - item.w * 0.5
		btn.anchor_right = item.x + item.w * 0.5
		btn.anchor_top = item.y - item.h * 0.5
		btn.anchor_bottom = item.y + item.h * 0.5
		btn.mouse_entered.connect(btn.grab_focus)
		btn.pressed.connect(_on_menu_pressed.bind(i))
		add_child(btn)
		buttons.append(btn)
	_move_highlight(0)

func _star_points(r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 8:
		var rad := r if i % 2 == 0 else r * 0.42
		var ang := TAU * i / 8.0 - PI * 0.5
		pts.append(Vector2(cos(ang), sin(ang)) * rad)
	return pts

func _move_highlight(idx: int) -> void:
	var item: Dictionary = MENU_ITEMS[idx]
	var vp := get_viewport_rect().size
	var center := Vector2(item.x * vp.x, item.y * vp.y)
	var size_px := Vector2(item.w * vp.x, item.h * vp.y)
	var cursor_r := size_px.y * 0.38
	cursor.position = center + Vector2(-size_px.x * 0.5 - cursor_r * 1.4, 0)
	cursor.scale = Vector2(cursor_r, cursor_r)
	underline.position = center + Vector2(-size_px.x * 0.5, size_px.y * 0.42)
	underline.size = Vector2(size_px.x * 1.06, maxf(2.0, vp.y * 0.004))

func _process(_delta: float) -> void:
	var idx := buttons.find(get_viewport().gui_get_focus_owner())
	if idx >= 0:
		_move_highlight(idx)

func _build_toast() -> void:
	toast = Label.new()
	toast.text = ""
	toast.add_theme_color_override("font_color", GOLD)
	toast.add_theme_font_override("font", GAME_FONT)
	toast.add_theme_font_size_override("font_size", 22)
	add_child(toast)

func _show_toast(msg: String) -> void:
	toast.text = msg
	toast.reset_size()
	var vp := get_viewport_rect().size
	toast.position = Vector2((vp.x - toast.size.x) * 0.5, vp.y * 0.80)
	toast.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(0.8)
	tw.tween_property(toast, "modulate:a", 0.0, 0.6)

func _build_settings() -> void:
	settings_popup = CanvasLayer.new()
	settings_popup.layer = 10
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.05, 0.04, 0.08, 0.72)
	settings_popup.add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#241F1A")
	sb.border_color = GOLD
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", sb)
	settings_popup.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 16)
	panel.add_child(vb)
	var title := Label.new()
	title.text = "设置"
	title.add_theme_color_override("font_color", GOLD)
	title.add_theme_font_size_override("font_size", 26)
	vb.add_child(title)
	var vol_row := HBoxContainer.new()
	vb.add_child(vol_row)
	var vol_label := Label.new()
	vol_label.text = "音量"
	vol_label.add_theme_color_override("font_color", Color("#D8CFC0"))
	vol_row.add_child(vol_label)
	var vol := HSlider.new()
	vol.min_value = 0.0
	vol.max_value = 1.0
	vol.step = 0.05
	vol.value = db_to_linear(AudioServer.get_bus_volume_db(0))
	vol.custom_minimum_size = Vector2(220, 24)
	vol.value_changed.connect(func(v: float) -> void:
		AudioServer.set_bus_volume_db(0, linear_to_db(maxf(v, 0.001))))
	vol_row.add_child(vol)
	var fs := CheckButton.new()
	fs.text = "全屏"
	fs.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	fs.toggled.connect(func(on: bool) -> void:
		DisplayServer.window_set_mode(
			DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED))
	vb.add_child(fs)
	var back := Button.new()
	back.text = "返回"
	back.pressed.connect(_close_settings)
	vb.add_child(back)
	settings_popup.visible = false

func _open_settings() -> void:
	settings_popup.visible = true
	busy = true

func _close_settings() -> void:
	settings_popup.visible = false
	busy = false
	buttons[0].grab_focus()

func _unhandled_input(event: InputEvent) -> void:
	if settings_popup.visible and event.is_action_pressed("ui_cancel"):
		_close_settings()
		get_viewport().set_input_as_handled()

func _on_menu_pressed(idx: int) -> void:
	if busy:
		return
	match idx:
		0:
			get_tree().change_scene_to_file("res://scenes/main.tscn")
		1:
			if FileAccess.file_exists("user://save.cfg"):
				get_tree().change_scene_to_file("res://scenes/main.tscn")
			else:
				_show_toast("暂无存档")
		2:
			_open_settings()
		3:
			get_tree().quit()

func _carousel_loop() -> void:
	while is_inside_tree():
		await get_tree().create_timer(CAROUSEL_INTERVAL).timeout
		if not is_inside_tree():
			return
		var next_i := (bg_index + 1) % BG_PATHS.size()
		bg_next.texture = load(BG_PATHS[next_i])
		bg_next.modulate.a = 0.0
		var tw := create_tween()
		tw.tween_property(bg_next, "modulate:a", 1.0, FADE_TIME)
		await tw.finished
		bg_current.texture = bg_next.texture
		bg_next.modulate.a = 0.0
		bg_index = next_i
