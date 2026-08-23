class_name HUD
extends CanvasLayer
## HUD：血条 / TV 条 / 回溯充能钟（12 s）/ 倒计时·斩杀·得分 / 技能栏 / 绑定盘 / 结算评级。

const INK := Color("#1A1714")
const RED := Color("#E9A0AC")
const GREY := Color("#4A443C")
const PAPER := Color("#F5F1E8")
const UI_TEXT_WHITE := Color("#F3FAFF")
const HP_CYAN := Color("#8FE7F5")
const TIME_BLUE := Color("#5FAEDB")
const TIME_HIGHLIGHT := Color("#C8F3FF")
const CLOCK_BLUE := Color("#78D7F4")
const CLOCK_IDLE := Color("#6D8498")
const SKILL_BLUE_BLACK := Color("#243744")

const SKILL_ART := {
	"time": preload("res://assets/ui/skill_time.png"),
	"thunder": preload("res://assets/ui/skill_thunder.png"),
	"quake": preload("res://assets/ui/skill_quake.png"),
	"ent": preload("res://assets/ui/skill_ent.png"),
	"flood": preload("res://assets/ui/skill_flood.png"),
	"swords": preload("res://assets/ui/skill_swords.png"),
}

const ZAN_TEX := preload("res://assets/ui/斩.png")
const SETTLE_BG := preload("res://assets/ui/Settlement/background.png")
const SETTLE_TITLE := preload("res://assets/ui/Settlement/title.png")
const SETTLE_BUTTON := preload("res://assets/ui/Settlement/button.png")
const HELP_BTN_TEX := preload("res://assets/ui/help/问号-进入按钮.png")
const HELP_PAGE_TEX := preload("res://assets/ui/help/主帮助页面.png")
const HELP_CLOSE_TEX := preload("res://assets/ui/help/关闭按钮.png")
## 帮助页尺寸（原 900×562 的 87%）与关闭按钮位置（贴主图右上角边缘）。
const HELP_PAGE_SIZE := Vector2(784.0, 489.0)
const HELP_CLOSE_SIZE := 48.0

## 每次启动游戏只在首个战斗场景自动弹一次帮助页（场景 reload 不重弹）。
static var _auto_help_done := false

var game
var font: Font
var board: Control
var dial_clock_tex: Texture2D
var dial_outer_clock_tex: Texture2D
var dial_pointer_tex: Texture2D

var help_btn: TextureButton
var help_overlay: Control

class _Board extends Control:
	var hud: HUD
	func _draw() -> void:
		if hud != null:
			hud._paint(self)

func _ready() -> void:
	font = load("res://assets/fonts/MFYueYuan_Noncommercial-Regular.ttf")
	dial_clock_tex = load("res://assets/ui/hud_top_clock.png")
	dial_outer_clock_tex = load("res://assets/art/effects/dial_clock.png")
	dial_pointer_tex = load("res://assets/art/effects/dial_pointer.png")
	board = _Board.new()
	board.hud = self
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(board)
	_build_help()
	# 首次作为主场景运行时自动弹帮助页（测试里 Game 是手动 new 的，不弹）
	if not _auto_help_done and get_tree().current_scene == game:
		_auto_help_done = true
		_open_help.call_deferred()

func _process(_delta: float) -> void:
	# 结算时藏起问号入口，别飘在结算页上
	if help_btn == null or game == null:
		return
	help_btn.visible = game.state != game.State.GAMEOVER

func _build_help() -> void:
	help_btn = TextureButton.new()
	help_btn.texture_normal = HELP_BTN_TEX
	help_btn.ignore_texture_size = true
	help_btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	help_btn.anchor_left = 1.0
	help_btn.anchor_right = 1.0
	help_btn.anchor_top = 0.0
	help_btn.anchor_bottom = 0.0
	help_btn.offset_left = -96.0
	help_btn.offset_right = -24.0
	help_btn.offset_top = 24.0
	help_btn.offset_bottom = 96.0
	help_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	help_btn.pressed.connect(_open_help)
	add_child(help_btn)

func _open_help() -> void:
	if help_overlay == null:
		_build_help_overlay()
	get_tree().paused = true
	help_overlay.visible = true

func _close_help() -> void:
	if help_overlay == null or not help_overlay.visible:
		return
	help_overlay.visible = false
	get_tree().paused = false

## 点帮助页任意位置都算关闭（只认鼠标按下；gui_input 里鼠标移动也来，不能全关）。
func _on_help_click(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed:
		_close_help()

func _build_help_overlay() -> void:
	help_overlay = Control.new()
	help_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	help_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	# 点击任意处关闭
	help_overlay.gui_input.connect(_on_help_click)
	# 半透明遮罩：挡住底下游戏输入；点击穿透给 overlay 统一处理关闭
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.05, 0.10, 0.78)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	help_overlay.add_child(dim)
	# 帮助页整图：居中（原 900×562 的 72%）
	var page := TextureRect.new()
	page.texture = HELP_PAGE_TEX
	page.ignore_texture_size = true
	page.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.set_anchors_preset(Control.PRESET_CENTER)
	page.offset_left = -HELP_PAGE_SIZE.x * 0.5
	page.offset_right = HELP_PAGE_SIZE.x * 0.5
	page.offset_top = -HELP_PAGE_SIZE.y * 0.5
	page.offset_bottom = HELP_PAGE_SIZE.y * 0.5
	help_overlay.add_child(page)
	# 关闭按钮：贴在帮助页右上角边缘（中心对齐页面顶角）
	var close_btn := TextureButton.new()
	close_btn.texture_normal = HELP_CLOSE_TEX
	close_btn.ignore_texture_size = true
	close_btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	close_btn.anchor_left = 1.0
	close_btn.anchor_right = 1.0
	close_btn.anchor_top = 0.0
	close_btn.anchor_bottom = 0.0
	var page_right: float = 1152.0 * 0.5 + HELP_PAGE_SIZE.x * 0.5
	var page_top: float = 648.0 * 0.5 - HELP_PAGE_SIZE.y * 0.5
	# anchor_right=1 时 offset 相对右边缘，须减视口宽换算成负偏移
	close_btn.offset_left = page_right - HELP_CLOSE_SIZE * 0.5 - 1152.0
	close_btn.offset_right = page_right + HELP_CLOSE_SIZE * 0.5 - 1152.0
	close_btn.offset_top = page_top - HELP_CLOSE_SIZE * 0.5
	close_btn.offset_bottom = page_top + HELP_CLOSE_SIZE * 0.5
	close_btn.pressed.connect(_close_help)
	help_overlay.add_child(close_btn)
	help_overlay.visible = false
	add_child(help_overlay)

func request_redraw() -> void:
	if board != null:
		board.queue_redraw()

## 世界坐标 → HUD 屏幕坐标（相机跟随+zoom 后伤害数字才能对上怪）
func _world_to_screen(p: Vector2) -> Vector2:
	var cam = game.camera
	if cam == null:
		return p
	return (p - cam.position) * cam.zoom + Vector2(576.0, 324.0)

func _paint(r: Control) -> void:
	if game == null:
		return
	var w := 1152.0
	var h := 648.0
	# —— 结算：战斗 HUD 全部不画，防技能栏等穿帮到结算页上 ——
	if game.state == game.State.GAMEOVER:
		_paint_settle(r, w, h)
		return
	# —— 全屏调子 ——
	if game.state == game.State.SPELL:
		r.draw_rect(Rect2(0, 0, w, h), Color(0.1, 0.12, 0.16, 0.08))
	if game.state == game.State.REWIND:
		r.draw_rect(Rect2(0, 0, w, h), Color(0.75, 0.22, 0.17, 0.12))
	if game.flash_t > 0.0:
		r.draw_rect(Rect2(0, 0, w, h),
			Color(1, 1, 1, game.flash_t / game.FLASH_TIME))
	if game.hit_flash > 0.0:
		r.draw_rect(Rect2(0, 0, w, h),
			Color(0.75, 0.2, 0.15, 0.22 * clampf(game.hit_flash / 0.25, 0.0, 1.0)))
	# 血条 / 时间值环 已移到 main.gd `_paint_dial`（与表盘同一 PaintLayer，同层级绘制）
	# —— 右上：斩杀 / 得分（时滞已移除：血量归零直接结算） ——
	var stat := "斩 %d    分 %d    ×%.1f" % [
		game.kills, int(round(game.score)), game.score_mult]
	_text(r, Vector2(w - 112.0, 14), stat, 18, UI_TEXT_WHITE, HORIZONTAL_ALIGNMENT_RIGHT, 420.0)
	_text(r, Vector2(w - 112.0, 38), "已撑 %.0fs" % game.run_time,
		14, Color(GREY.r, GREY.g, GREY.b, 0.7), HORIZONTAL_ALIGNMENT_RIGHT, 420.0)
	# —— 顶部中央：回溯充能钟 ——
	var c := Vector2(w * 0.5, 76.0)
	var rad := 46.0
	var t: float = clampf(game.clock_charge / game.CLOCK_TIME, 0.0, 1.0)
	var ready: bool = game.clock_charge >= game.CLOCK_TIME
	var ring_col := Color(CLOCK_IDLE.r, CLOCK_IDLE.g, CLOCK_IDLE.b, 0.8)
	if ready:
		var pulse := 0.5 + 0.5 * sin(game.sim_time * 8.0)
		ring_col = Color(CLOCK_BLUE.r, CLOCK_BLUE.g, CLOCK_BLUE.b, 0.55 + 0.45 * pulse)
	if dial_outer_clock_tex != null:
		r.draw_texture_rect(dial_outer_clock_tex, Rect2(c - Vector2(rad * 1.24, rad * 1.24), Vector2(rad * 2.48, rad * 2.48)), false,
			Color(1.0, 1.0, 1.0, 0.62))
	# 白色表盘面已去掉：只留细描边圆环做底盘
	r.draw_arc(c, rad, 0.0, TAU, 48, ring_col, 2.0)
	if dial_pointer_tex != null:
		var pointer_size := Vector2(40.0, 8.0)
		var pointer_transform := Transform2D(-PI / 2.0 + TAU * t, c)
		pointer_transform = pointer_transform.translated_local(Vector2(0.0, -pointer_size.y * 0.5))
		r.draw_set_transform_matrix(pointer_transform)
		r.draw_texture_rect(dial_pointer_tex, Rect2(Vector2.ZERO, pointer_size), false, ring_col)
		r.draw_set_transform_matrix(Transform2D.IDENTITY)
	else:
		var mang := -PI / 2.0 + TAU * t
		r.draw_line(c, c + Vector2(cos(mang), sin(mang)) * 23.0, ring_col, 2.5)
	if ready:
		var blink := 0.55 + 0.45 * sin(game.sim_time * 6.0)
		# 提示字挪进表盘中盘；深浅蓝折中色
		var rc := Color("#4B92C7", blink)
		_text_center(r, c.x - 0.5, c.y - 22.0, "按R", 16, rc)
		_text_center(r, c.x + 0.5, c.y - 22.0, "按R", 16, rc)
		_text_center(r, c.x - 0.5, c.y + 2.0, "回溯", 24, rc)
		_text_center(r, c.x + 0.5, c.y + 2.0, "回溯", 24, rc)
	# —— 底部：咒语栏 ——
	_paint_skills(r, w, h)
	# —— 公告 ——
	if game.announce_t > 0.0:
		var aa: float = clampf(game.announce_t / 1.6, 0.0, 1.0)
		aa = aa * aa
		_text_center(r, w * 0.5, 150.0, game.announce_text, 34,
			Color(INK.r, INK.g, INK.b, aa))
	# —— 技能图：中心展开 → 左右扫描显现，完整停留 2 秒 ——
	_paint_skill_art(r, w, h)
	# —— 伤害数字 ——
	for n in game.numbers:
		var k: float = n.t / 0.8
		var a: float = clampf(1.0 - k, 0.0, 1.0)
		var size: int = 42 if n.red else 30
		var pop := 1.0 + 0.6 * clampf((0.12 - n.t) / 0.12, 0.0, 1.0)
		var col := Color(RED.r, RED.g, RED.b, a) if n.red else Color(0.35, 0.75, 1.0, a)
		var pos: Vector2 = _world_to_screen(n.pos) + Vector2(0, -60.0 * k) + Vector2(0, -float(size))
		_text_center(r, pos.x, pos.y, str(n.val), int(float(size) * pop), col)
	# —— 「斬」/「回溯」/技能大字 ——
	if game.zan_t > 0.0:
		var za: float = clampf(game.zan_t / 0.5, 0.0, 1.0)
		if game.zan_text == "斬":
			var tex: Texture2D = ZAN_TEX
			var max_size := Vector2(430.0, 242.0)
			var size := max_size * (0.65 + 0.35 * clampf((0.5 - game.zan_t) / 0.35, 0.0, 1.0))
			var rect := Rect2(Vector2(w, h) * 0.5 - size * 0.5, size)
			r.draw_texture_rect(tex, rect, false, Color(1, 1, 1, za))
		else:
			var zcol := Color(RED.r, RED.g, RED.b, za) if game.zan_red else Color(INK.r, INK.g, INK.b, za)
			_text_center(r, w * 0.5, h * 0.42, game.zan_text, 150, zcol)
	# —— 觉醒选碑面板 ——
	if game.bind_panel:
		_paint_bind(r, w, h)
	# 结算已提前在 _paint 开头处理（GAMEOVER 时战斗 HUD 不画）

## 觉醒面板：只列还空着的碑，序号就是要按的键。
func _paint_skill_art(r: Control, w: float, h: float) -> void:
	if game.skill_art_t <= 0.0 or not SKILL_ART.has(game.skill_art_id):
		return
	var elapsed: float = game.SKILL_ART_DURATION - game.skill_art_t
	var grow: float = clampf(elapsed / 0.35, 0.0, 1.0)
	var scan: float = clampf((elapsed - 0.18) / 0.55, 0.0, 1.0)
	var fade: float = clampf(game.skill_art_t / 0.35, 0.0, 1.0)
	var tex: Texture2D = SKILL_ART[game.skill_art_id]
	var max_size := Vector2(430.0, 242.0)
	var size := max_size * (0.65 + 0.35 * grow)
	var rect := Rect2(Vector2(w, h) * 0.5 - size * 0.5, size)
	var reveal := Rect2(rect.position, Vector2(rect.size.x * scan, rect.size.y))
	if scan > 0.0:
		r.draw_texture_rect_region(tex, reveal, Rect2(0, 0, tex.get_width() * scan, tex.get_height()), Color(1, 1, 1, fade))
		var x := rect.position.x + rect.size.x * scan
		r.draw_line(Vector2(x, rect.position.y), Vector2(x, rect.end.y), Color(0.75, 0.94, 1.0, fade), 2.0)

func _paint_bind(r: Control, w: float, h: float) -> void:
	r.draw_rect(Rect2(0, 0, w, h), Color(0.05, 0.045, 0.04, 0.72))
	_text_center(r, w * 0.5, h * 0.24, "神纹觉醒", 48, PAPER)
	_text_center(r, w * 0.5, h * 0.24 + 62.0,
		"这一笔的纹路可刻上一块空碑 · 按序号选定并立即施展 · Esc 放弃（本局不可改）",
		18, Color(0.78, 0.76, 0.71))
	var blank: Array = game.blank_slots()
	var y := h * 0.44
	for i in blank.size():
		var s: Dictionary = game.skills[int(blank[i])]
		_text_center(r, w * 0.5, y, "%d · %s   冷却 %.0fs" % [
			i + 1, String(s.name), float(s.cd)], 22, PAPER)
		y += 34.0

## 神纹录：古代神纹出生即亮，普通神纹要战斗中被长笔画点亮。
func _paint_skills(r: Control, w: float, h: float) -> void:
	var n: int = game.skills.size()
	var cw := 118.0
	var total := cw * float(n)
	var x0 := (w - total) * 0.5
	var y := h - 52.0
	for i in n:
		var s: Dictionary = game.skills[i]
		var x := x0 + cw * float(i)
		var bound: bool = bool(s.bound)
		var cool: float = float(s.cd_left)
		var box := Rect2(x + 4.0, y, cw - 8.0, 40.0)
		r.draw_rect(box, Color(SKILL_BLUE_BLACK.r, SKILL_BLUE_BLACK.g, SKILL_BLUE_BLACK.b, 0.32))
		r.draw_rect(box, Color(CLOCK_IDLE.r, CLOCK_IDLE.g, CLOCK_IDLE.b, 0.55), false, 1.0)
		if cool > 0.0:
			var f: float = clampf(cool / float(s.cd), 0.0, 1.0)
			r.draw_rect(Rect2(box.position.x, box.position.y, box.size.x * f, box.size.y),
				Color(0, 0, 0, 0.22))
		var name_col := UI_TEXT_WHITE
		if not bound:
			name_col = Color(UI_TEXT_WHITE.r, UI_TEXT_WHITE.g, UI_TEXT_WHITE.b, 0.45)
		elif cool <= 0.0:
			name_col = UI_TEXT_WHITE
		_text_center(r, x + cw * 0.5, y + 4.0, String(s.name) if bound else "空碑", 14, name_col)
		var note := "古纹" if bool(s.ancient) else ("神纹" if bound else "待觉醒")
		if cool > 0.0:
			note = "%.1fs" % cool
		_text_center(r, x + cw * 0.5, y + 22.0, note, 12,
			Color(UI_TEXT_WHITE.r, UI_TEXT_WHITE.g, UI_TEXT_WHITE.b, 0.75))

func _paint_settle(r: Control, w: float, h: float) -> void:
	# 静态背景图（视频背景在有机器上花屏，先回退）
	r.draw_texture_rect(SETTLE_BG, Rect2(0, 0, w, h), false)
	r.draw_rect(Rect2(0, 0, w, h), Color(0.03, 0.08, 0.17, 0.10))

	# 美术原图是透明大画布；region 只取有效区域，避免空白把版面挤散。
	# 标题：整区域绘制（粗笔清晰优先，接受缩放轻微锯齿）；代码副标题已删，图内自带一行。
	r.draw_texture_rect_region(SETTLE_TITLE, Rect2(36, 28, 270, 150),
		Rect2(62, 196, 1322, 710))
	_text(r, Vector2(66, 202), "击 杀 积 分", 16, Color("#B8D3ED"))
	_text(r, Vector2(62, 220), "%s" % _fmt_score(game.score), 76, Color.WHITE)

	var stats := [
		["斩杀数", "%d" % game.kills],
		["连斩倍率", "×%.1f" % game.score_mult],
		["时砂收集", "%d" % game.payout_sand],
		["轮回评级", game.rating],
		["本局时长", _fmt(game.run_time)],
	]
	var y := 322.0
	for stat in stats:
		_text(r, Vector2(66, y), String(stat[0]), 18, Color("#DCE9F7"))
		_text(r, Vector2(342, y - 2.0), String(stat[1]), 26, Color.WHITE,
			HORIZONTAL_ALIGNMENT_RIGHT, 160.0)
		r.draw_line(Vector2(66, y + 29.0), Vector2(502, y + 29.0), Color(0.68, 0.82, 0.96, 0.24), 1.0)
		y += 42.0

	# 结算按钮：常态半暗（50%），鼠标移入全亮（结算页无控件节点，用鼠标坐标命中测试）
	var btn_rect := Rect2(47.0, 526.0, 312.0, 94.0)
	var hover: bool = btn_rect.has_point(board.get_viewport().get_mouse_position())
	var btn_a := 0.5
	if hover:
		btn_a = 0.9 + 0.1 * sin(game.sim_time * 4.0)
	r.draw_texture_rect_region(SETTLE_BUTTON, btn_rect,
		Rect2(33, 318, 1391, 418), Color(1.0, 1.0, 1.0, btn_a))

func _fmt_score(v: float) -> String:
	var raw := str(int(round(v)))
	var out := ""
	for i in raw.length():
		if i > 0 and (raw.length() - i) % 3 == 0:
			out += ","
		out += raw[i]
	return out

func _text(r: Control, pos: Vector2, s: String, size: int, col: Color,
		align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	r.draw_string(font, Vector2(pos.x, pos.y + size), s, align, width, size, col)

func _text_center(r: Control, cx: float, top: float, s: String, size: int, col: Color) -> void:
	var tw := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	_text(r, Vector2(cx - tw * 0.5, top), s, size, col)

static func _fmt(t: float) -> String:
	return "%02d:%02d" % [int(t) / 60, int(t) % 60]
