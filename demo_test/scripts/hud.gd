class_name HUD
extends CanvasLayer
## HUD：血条 / 墨条 / 时钟（分针追时针）/ 波次·斩杀·时间 / 大数字 / 斬 / 白闪 / 结算。

const INK := Color("#1A1714")
const RED := Color("#C0392B")
const GREY := Color("#4A443C")
const PAPER := Color("#F5F1E8")

var game
var font: SystemFont
var board: Control

class _Board extends Control:
	var hud: HUD
	func _draw() -> void:
		if hud != null:
			hud._paint(self)

func _ready() -> void:
	font = SystemFont.new()
	font.font_names = PackedStringArray([
		"Microsoft YaHei UI", "Microsoft YaHei", "SimHei", "Noto Sans CJK SC"])
	board = _Board.new()
	board.hud = self
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(board)

func request_redraw() -> void:
	if board != null:
		board.queue_redraw()

func _paint(r: Control) -> void:
	if game == null:
		return
	var w := 1152.0
	var h := 648.0
	# —— 全屏调子 ——
	if game.state == game.State.DRAW:
		r.draw_rect(Rect2(0, 0, w, h), Color(0, 0, 0, 0.05))
	if game.state == game.State.SPELL_DRAW:
		r.draw_rect(Rect2(0, 0, w, h), Color(0.32, 0.68, 0.62, 0.04))
	if game.state == game.State.REWIND:
		r.draw_rect(Rect2(0, 0, w, h), Color(0.75, 0.22, 0.17, 0.12))
	if game.flash_t > 0.0:
		r.draw_rect(Rect2(0, 0, w, h),
			Color(1, 1, 1, game.flash_t / game.FLASH_TIME))
	if game.hit_flash > 0.0:
		r.draw_rect(Rect2(0, 0, w, h),
			Color(0.75, 0.2, 0.15, 0.22 * clampf(game.hit_flash / 0.25, 0.0, 1.0)))
	# —— 左上：血条 / 墨条 ——
	var hp_f: float = clampf(game.player.hp / game.player.max_hp, 0.0, 1.0)
	r.draw_rect(Rect2(20, 16, 220, 14), Color(0, 0, 0, 0.10))
	r.draw_rect(Rect2(20, 16, 220.0 * hp_f, 14), RED)
	r.draw_rect(Rect2(20, 16, 220, 14), Color(0, 0, 0, 0.35), false, 1.0)
	_text(r, Vector2(244, 14), "体", 13, GREY)
	var ink_f: float = clampf(game.ink / game.ink_max(), 0.0, 1.0)
	r.draw_rect(Rect2(20, 42, 220, 10), Color(0, 0, 0, 0.10))
	var ink_col := INK if not game.dry_pen else GREY
	r.draw_rect(Rect2(20, 42, 220.0 * ink_f, 10), ink_col)
	r.draw_rect(Rect2(20, 42, 220, 10), Color(0, 0, 0, 0.35), false, 1.0)
	_text(r, Vector2(244, 36), "墨", 13, GREY)
	# —— 时间值 TV 条（施法资源，淡青） ——
	var tv_f: float = clampf(game.time_value / game.TIME_VALUE_MAX, 0.0, 1.0)
	r.draw_rect(Rect2(20, 62, 220, 10), Color(0, 0, 0, 0.10))
	var tv_col := Color(0.32, 0.68, 0.62)
	if game.time_value < game.TV_MIN_CAST:
		tv_col = Color(0.32, 0.68, 0.62, 0.45 + 0.4 * absf(sin(game.sim_time * 8.0)))
	r.draw_rect(Rect2(20, 62, 220.0 * tv_f, 10), tv_col)
	r.draw_rect(Rect2(20, 62, 220, 10), Color(0, 0, 0, 0.35), false, 1.0)
	_text(r, Vector2(244, 56), "时", 13, GREY)
	# —— 右上：波次 / 斩杀 / 得分 / 倒计时 ——
	var stat := "波 %d    斩 %d    分 %d" % [game.wave_idx, game.kills, game.score]
	_text(r, Vector2(w - 20.0, 14), stat, 18, GREY, HORIZONTAL_ALIGNMENT_RIGHT, 340.0)
	# 倒计时（右上角，时间不多时变红提示）
	var t_left := int(ceilf(game.round_timer))
	var t_col := RED if t_left <= 10 else GREY
	_text(r, Vector2(w - 20.0, 36), "%d s" % t_left, 22, t_col, HORIZONTAL_ALIGNMENT_RIGHT, 100.0)
	# —— 顶部中央：时钟（分针追时针） ——
	var c := Vector2(w * 0.5, 66.0)
	var rad := 30.0
	var t: float = clampf(game.clock_charge / game.CLOCK_TIME, 0.0, 1.0)
	var ready: bool = game.clock_charge >= game.CLOCK_TIME
	var ring_col := Color(GREY.r, GREY.g, GREY.b, 0.8)
	if ready:
		var pulse := 0.5 + 0.5 * sin(game.sim_time * 8.0)
		ring_col = Color(RED.r, RED.g, RED.b, 0.55 + 0.45 * pulse)
	r.draw_arc(c, rad, 0.0, TAU, 48, ring_col, 2.0)
	# 充能弧（红）
	if t > 0.0 and t < 1.0:
		r.draw_arc(c, rad + 5.0, -PI / 2.0, -PI / 2.0 + TAU * t, 48,
			Color(RED.r, RED.g, RED.b, 0.45), 2.5)
	# 时针（固定 12 点）
	r.draw_line(c, c + Vector2(0, -17), ring_col, 4.0)
	# 分针（追一圈）
	var mang := -PI / 2.0 + TAU * t
	r.draw_line(c, c + Vector2(cos(mang), sin(mang)) * 23.0, ring_col, 2.5)
	r.draw_circle(c, 2.5, ring_col)
	if ready:
		var blink := 0.55 + 0.45 * sin(game.sim_time * 6.0)
		_text_center(r, c.x, 104.0, "R · 回溯", 16, Color(RED.r, RED.g, RED.b, blink))
	# —— 波次预告 ——
	if game.announce_t > 0.0:
		var aa: float = clampf(game.announce_t / 1.6, 0.0, 1.0)
		aa = aa * aa
		_text_center(r, w * 0.5, 150.0, game.announce_text, 34,
			Color(INK.r, INK.g, INK.b, aa))
	# —— 伤害数字 ——
	for n in game.numbers:
		var k: float = n.t / 0.8
		var a: float = clampf(1.0 - k, 0.0, 1.0)
		var size: int = 42 if n.red else 30
		var pop := 1.0 + 0.6 * clampf((0.12 - n.t) / 0.12, 0.0, 1.0)
		var col := Color(RED.r, RED.g, RED.b, a) if n.red else Color(INK.r, INK.g, INK.b, a)
		var pos: Vector2 = n.pos + Vector2(0, -60.0 * k) + Vector2(0, -float(size))
		_text_center(r, pos.x, pos.y, str(n.val), int(float(size) * pop), col)
	# —— 「斬」/「回溯」 ——
	if game.zan_t > 0.0:
		var za: float = clampf(game.zan_t / 0.5, 0.0, 1.0)
		var zcol := Color(RED.r, RED.g, RED.b, za) if game.zan_red else Color(INK.r, INK.g, INK.b, za)
		_text_center(r, w * 0.5, h * 0.42, game.zan_text, 150, zcol)
	# —— 新手提示 ——
	if game.kills == 0 and game.help_t > 0.0:
		var ha: float = clampf(game.help_t, 0.0, 1.0)
		_text_center(r, w * 0.5, h - 34.0,
			"左键按住 画墨 · 松开 冲斩 · 右键按住 画咒施法 · 时钟满按 R 回溯",
			15, Color(GREY.r, GREY.g, GREY.b, ha * 0.85))
	# —— 施法提示 ——
	if game.state == game.State.SPELL_DRAW:
		var blink := 0.55 + 0.45 * sin(game.sim_time * 10.0)
		_text_center(r, w * 0.5, h - 34.0, "松开右键 · 施放咒语（时/火/风）",
			16, Color(0.32, 0.68, 0.62, blink))
	# —— 结算 ——
	if game.state == game.State.GAMEOVER:
		r.draw_rect(Rect2(0, 0, w, h), Color(0.05, 0.045, 0.04, 0.82))
		_text_center(r, w * 0.5, h * 0.30, "时 尽", 72, PAPER)
		var rt := _rating(game.score)
		_text_center(r, w * 0.5, h * 0.30 + 84.0,
			"得分 %d · 斩杀 %d · 最高连击 %d · 评级 %s" % [game.score, game.kills, game.max_combo, rt],
			22, Color(0.78, 0.76, 0.71))
		var blink2 := 0.55 + 0.45 * sin(game.sim_time * 5.0)
		_text_center(r, w * 0.5, h * 0.30 + 128.0, "点击 / 回车 · 重开一局",
			18, Color(RED.r, RED.g, RED.b, blink2))

static func _rating(score: int) -> String:
	if score >= 4500:
		return "SS"
	if score >= 3000:
		return "S"
	if score >= 1800:
		return "A"
	if score >= 900:
		return "B"
	return "C"

func _text(r: Control, pos: Vector2, s: String, size: int, col: Color,
		align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	r.draw_string(font, Vector2(pos.x, pos.y + size), s, align, width, size, col)

func _text_center(r: Control, cx: float, top: float, s: String, size: int, col: Color) -> void:
	var tw := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	_text(r, Vector2(cx - tw * 0.5, top), s, size, col)

static func _fmt(t: float) -> String:
	return "%02d:%02d" % [int(t) / 60, int(t) % 60]
