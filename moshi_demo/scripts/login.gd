extends Control
## 登录页（标题屏）「时之回环」。
## UI 文字烧在背景整图里，本脚本只叠：背景 5 态轮播、开始按钮（双态贴图）。

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

## 开始按钮贴图：未激活态常态显示，激活态在 hover/focus/pressed 时切换。
const BTN_INACTIVE_PATH := "res://assets/art/login/btn_start_inactive.png"
const BTN_ACTIVE_PATH := "res://assets/art/login/btn_start_active.png"
## 开始按钮热区（中心/尺寸为视口百分比）
const BTN_START := {"x": 0.26, "y": 0.615, "w": 0.42, "h": 0.208}

var bg_current: TextureRect
var bg_next: TextureRect
var bg_video: VideoStreamPlayer
var bg_index := 0
var start_btn: TextureButton
var btn_active_tex: Texture2D
var btn_inactive_tex: Texture2D

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	add_theme_font_override("font", GAME_FONT)
	_load_button_textures()
	_build_background()
	_build_start_button()
	if bg_video == null:
		_carousel_loop()

func _load_button_textures() -> void:
	if not ResourceLoader.exists(BTN_INACTIVE_PATH):
		push_error("开始按钮未激活态贴图缺失: " + BTN_INACTIVE_PATH)
	if not ResourceLoader.exists(BTN_ACTIVE_PATH):
		push_error("开始按钮激活态贴图缺失: " + BTN_ACTIVE_PATH)
	btn_inactive_tex = load(BTN_INACTIVE_PATH)
	btn_active_tex = load(BTN_ACTIVE_PATH)

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

func _build_start_button() -> void:
	start_btn = TextureButton.new()
	start_btn.focus_mode = Control.FOCUS_ALL
	start_btn.texture_normal = btn_inactive_tex
	start_btn.texture_hover = btn_active_tex
	start_btn.texture_focused = btn_active_tex
	start_btn.texture_pressed = btn_active_tex
	start_btn.ignore_texture_size = true
	start_btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	start_btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	start_btn.anchor_left = BTN_START.x - BTN_START.w * 0.5
	start_btn.anchor_right = BTN_START.x + BTN_START.w * 0.5
	start_btn.anchor_top = BTN_START.y - BTN_START.h * 0.5
	start_btn.anchor_bottom = BTN_START.y + BTN_START.h * 0.5
	start_btn.mouse_entered.connect(start_btn.grab_focus)
	start_btn.mouse_exited.connect(start_btn.release_focus)
	start_btn.pressed.connect(_on_start_pressed)
	add_child(start_btn)

func _on_start_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept") and start_btn.has_focus():
		_on_start_pressed()
		get_viewport().set_input_as_handled()

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
