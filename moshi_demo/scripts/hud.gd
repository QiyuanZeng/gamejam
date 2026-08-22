class_name HUD
extends CanvasLayer
## HUD：血条 / TV 条 / 回溯充能钟（12 s）/ 倒计时·斩杀·得分 / 技能栏 / 绑定盘 / 结算评级。

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
	if game.state == game.State.SPELL:
		r.draw_rect(Rect2(0, 0, w, h), Color(0.1, 0.12, 0.16, 0.08))
	if game.state == game.State.REWIND:
		r.draw_rect(Rect2(0, 0, w, h), Color(0.75, 0.22, 0.17, 0.12))
	if game.state == game.State.LAG:
		r.draw_rect(Rect2(0, 0, w, h), Color(0.2, 0.18, 0.16, 0.35))
	if game.flash_t > 0.0:
		r.draw_rect(Rect2(0, 0, w, h),
			Color(1, 1, 1, game.flash_t / game.FLASH_TIME))
	if game.hit_flash > 0.0:
		r.draw_rect(Rect2(0, 0, w, h),
			Color(0.75, 0.2, 0.15, 0.22 * clampf(game.hit_flash / 0.25, 0.0, 1.0)))
	# —— 左上：血条 / TV 条 ——
	var hp_f: float = clampf(game.player.hp / game.player.max_hp, 0.0, 1.0)
	r.draw_rect(Rect2(20, 16, 220, 14), Color(0, 0, 0, 0.10))
	r.draw_rect(Rect2(20, 16, 220.0 * hp_f, 14), RED)
	r.draw_rect(Rect2(20, 16, 220, 14), Color(0, 0, 0, 0.35), false, 1.0)
	_text(r, Vector2(244, 14), "体", 13, GREY)
	var tv_f: float = clampf(game.tv / game.tv_max(), 0.0, 1.0)
	r.draw_rect(Rect2(20, 42, 220, 10), Color(0, 0, 0, 0.10))
	var tv_col := INK if not game.dry_pen else GREY
	r.draw_rect(Rect2(20, 42, 220.0 * tv_f, 10), tv_col)
	r.draw_rect(Rect2(20, 42, 220, 10), Color(0, 0, 0, 0.35), false, 1.0)
	# 觉醒线刻度：这一笔要烧掉起笔余额的 BIND_ENERGY_RATIO，条子掉到这条线以下才够格点亮空碑。
	# 没在书写时按当下余额预演 —— 告诉玩家「现在起笔的话得画到哪儿」。
	var base: float = game.draw_tv0 if game.state == game.State.SPELL else game.tv
	var bx: float = 20.0 + 220.0 * clampf(
		base * (1.0 - game.BIND_ENERGY_RATIO) / game.tv_max(), 0.0, 1.0)
	r.draw_line(Vector2(bx, 40), Vector2(bx, 54), Color(RED.r, RED.g, RED.b, 0.6), 1.5)
	_text(r, Vector2(244, 36), "时 %d" % int(game.tv), 13, GREY)
	# —— 右上：体力 / 斩杀 / 得分 ——
	# 本局没有时限，唯一的结束条件是体力（时滞次数）耗尽，所以这里常驻显示体力。
	var stam: int = maxi(game.LAG_MAX - game.lag_count, 0)
	var stat := "体力 %d/%d    斩 %d    分 %d    ×%.1f" % [
		stam, game.LAG_MAX, game.kills, int(round(game.score)), game.score_mult]
	_text(r, Vector2(w - 20.0, 14), stat, 18,
		GREY if stam > 1 else Color(RED.r, RED.g, RED.b, 0.9),
		HORIZONTAL_ALIGNMENT_RIGHT, 420.0)
	_text(r, Vector2(w - 20.0, 38), "已撑 %.0fs" % game.run_time,
		14, Color(GREY.r, GREY.g, GREY.b, 0.7), HORIZONTAL_ALIGNMENT_RIGHT, 420.0)
	# —— 顶部中央：回溯充能钟（12 s） ——
	var c := Vector2(w * 0.5, 66.0)
	var rad := 30.0
	var t: float = clampf(game.clock_charge / game.CLOCK_TIME, 0.0, 1.0)
	var ready: bool = game.clock_charge >= game.CLOCK_TIME
	var ring_col := Color(GREY.r, GREY.g, GREY.b, 0.8)
	if ready:
		var pulse := 0.5 + 0.5 * sin(game.sim_time * 8.0)
		ring_col = Color(RED.r, RED.g, RED.b, 0.55 + 0.45 * pulse)
	r.draw_arc(c, rad, 0.0, TAU, 48, ring_col, 2.0)
	if t > 0.0 and t < 1.0:
		r.draw_arc(c, rad + 5.0, -PI / 2.0, -PI / 2.0 + TAU * t, 48,
			Color(RED.r, RED.g, RED.b, 0.45), 2.5)
	r.draw_line(c, c + Vector2(0, -17), ring_col, 4.0)
	var mang := -PI / 2.0 + TAU * t
	r.draw_line(c, c + Vector2(cos(mang), sin(mang)) * 23.0, ring_col, 2.5)
	r.draw_circle(c, 2.5, ring_col)
	if ready:
		var blink := 0.55 + 0.45 * sin(game.sim_time * 6.0)
		_text_center(r, c.x, 104.0, "R · 回溯", 16, Color(RED.r, RED.g, RED.b, blink))
	# —— 底部：咒语栏 ——
	_paint_skills(r, w, h)
	# —— 公告 ——
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
	# —— 「斬」/「回溯」/技能大字 ——
	if game.zan_t > 0.0:
		var za: float = clampf(game.zan_t / 0.5, 0.0, 1.0)
		var zcol := Color(RED.r, RED.g, RED.b, za) if game.zan_red else Color(INK.r, INK.g, INK.b, za)
		_text_center(r, w * 0.5, h * 0.42, game.zan_text, 150, zcol)
	# —— 新手提示 ——
	if game.kills == 0 and game.help_t > 0.0:
		var ha: float = clampf(game.help_t, 0.0, 1.0)
		_text_center(r, w * 0.5, h - 96.0,
			"左键 表盘定向斩 · 按住右键 子弹时间书写（松开斩击，笔形对上即施咒）· R 回溯",
			15, Color(GREY.r, GREY.g, GREY.b, ha * 0.85))
	# —— 时滞 ——
	if game.state == game.State.LAG:
		_text_center(r, w * 0.5, h * 0.60, "时滞 %.1f" % maxf(game.lag_timer, 0.0),
			26, Color(RED.r, RED.g, RED.b, 0.85))
	# —— 觉醒选碑面板 ——
	if game.bind_panel:
		_paint_bind(r, w, h)
	# —— 结算 ——
	if game.state == game.State.GAMEOVER:
		_paint_settle(r, w, h)

## 觉醒面板：只列还空着的碑，序号就是要按的键。
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
		r.draw_rect(box, Color(0, 0, 0, 0.06))
		r.draw_rect(box, Color(0, 0, 0, 0.22), false, 1.0)
		if cool > 0.0:
			var f: float = clampf(cool / float(s.cd), 0.0, 1.0)
			r.draw_rect(Rect2(box.position.x, box.position.y, box.size.x * f, box.size.y),
				Color(0, 0, 0, 0.22))
		var name_col := GREY
		if not bound:
			name_col = Color(GREY.r, GREY.g, GREY.b, 0.35)
		elif cool <= 0.0:
			name_col = INK
		_text_center(r, x + cw * 0.5, y + 4.0, String(s.name) if bound else "空碑", 14, name_col)
		var note := "古纹" if bool(s.ancient) else ("神纹" if bound else "待觉醒")
		if cool > 0.0:
			note = "%.1fs" % cool
		_text_center(r, x + cw * 0.5, y + 22.0, note, 12,
			Color(GREY.r, GREY.g, GREY.b, 0.75))

func _paint_settle(r: Control, w: float, h: float) -> void:
	r.draw_rect(Rect2(0, 0, w, h), Color(0.05, 0.045, 0.04, 0.85))
	_text_center(r, w * 0.5, h * 0.16, "时 尽", 64, PAPER)
	_text_center(r, w * 0.5, h * 0.16 + 76.0, game.rating, 130,
		Color(RED.r, RED.g, RED.b, 0.95))
	var y := h * 0.16 + 218.0
	_text_center(r, w * 0.5, y, "总分 %d   ×%.1f 倍率   斩杀 %d" % [
		int(round(game.score)), game.score_mult, game.kills], 24, Color(0.82, 0.80, 0.75))
	_text_center(r, w * 0.5, y + 34.0, "金币 %d   时砂 %d   时滞 %d 次" % [
		game.payout_coins, game.payout_sand, game.lag_count], 20, Color(0.78, 0.76, 0.71))
	var blink := 0.55 + 0.45 * sin(game.sim_time * 5.0)
	_text_center(r, w * 0.5, y + 76.0, "点击 / 回车 · 重开一局",
		18, Color(RED.r, RED.g, RED.b, blink))

func _text(r: Control, pos: Vector2, s: String, size: int, col: Color,
		align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	r.draw_string(font, Vector2(pos.x, pos.y + size), s, align, width, size, col)

func _text_center(r: Control, cx: float, top: float, s: String, size: int, col: Color) -> void:
	var tw := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	_text(r, Vector2(cx - tw * 0.5, top), s, size, col)

static func _fmt(t: float) -> String:
	return "%02d:%02d" % [int(t) / 60, int(t) % 60]
