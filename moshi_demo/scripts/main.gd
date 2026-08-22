class_name Game
extends Node2D
## 《时间刺客》主控制器 —— 表盘 AP 斩击 + 子弹时间咒语 + 回溯引爆。
## 左键：沿时针指向固定距离斩击（消耗 1 AP，方案 A）。
## 右键：按住进子弹时间书写（扣 TV），松开沿笔画斩击；笔画匹配咒语则附加释放技能。
## 伤害沿用「标记—引爆」模型：掠过只挂标记，终点顿帧统一结算。

enum State { PLAY, SPELL, DASH, BURST, REWIND, LAG, GAMEOVER }

# ============================== §1 全局 ==============================

const ARENA := Vector2(1152.0, 648.0)
const RUN_LIMIT := 30.0
const PLAYER_HP := 100.0
const MAX_ENEMIES := 130
const SPAWN_MARGIN := 26.0

# ============================== §3 表盘 / 行动点 ==============================

const AP_MAX_BASE := 3
const AP_MAX_CAP := 6
const HOUR_PERIOD := 2.0          # AB §13：1.5 / 2.0 / 2.5
const SEC_PERIOD := 0.5
const MIN_PERIOD := 1.0
const AP_PER_HOUR := 1.0
const AP_PER_SEC := 0.25
const AP_PER_MIN := 0.25
const SLASH_MIN_GAP := 0.15
const DIAL_RADIUS := 40.0

const DASH_SPEED := 2400.0
const DASH_RADIUS := 70.0
const DASH_DMG := 20.0
const DASH_DIST_BASE := 260.0
const DASH_DIST_CAP := 400.0
const POST_DASH_INVULN := 0.3
const SAMPLE_DIST := 6.0

# ============================== §4 回溯 ==============================

const CLOCK_TIME := 12.0          # AB §13：10 / 12 / 15
const REWIND_SLOTS := 5
const REWIND_MULT := 0.5
const REWIND_PATH_TIME := 0.15
const BURST_FREEZE := 0.16
const MARK_RETAIN := 1.5

# ============================== §5 子弹时间 / 时间值 / 咒语 ==============================

const TV_MAX_BASE := 500.0
const TV_REGEN_BASE := 20.0
const TV_COST_PER_PX := 1.0       # 1 px 笔画 = 1 墨
const BULLET_FACTOR := 0.10       # AB §13：0.05 / 0.10 / 0.20
const BULLET_TV_DRAIN := 30.0
const BULLET_MIN_TIME := 0.2
const BULLET_EXIT_TV := 10.0
const BIND_THRESHOLD := 0.60      # AB §13：0.5 / 0.6 / 0.7
const SPELL_MIN_LEN := 120.0
const SPELL_DIR_SIM := 0.80
const SPELL_SAMPLES := 9          # 重采样点数 → 8 段方向序列

## _try_cast 结果：未命中 / 已释放（斩击照常）/ 已释放且接管状态（如「时」直接进回溯）
const CAST_NONE := 0
const CAST_DONE := 1
const CAST_TAKEOVER := 2

## 固定咒语笔形（单笔近似）：「时」取方回起手，「斩」取斜劈 Z 形。
static func fixed_stroke(id: String) -> PackedVector2Array:
	match id:
		"time":
			return PackedVector2Array([
				Vector2(0, 0), Vector2(58, 0), Vector2(58, 46), Vector2(8, 46), Vector2(8, 16)])
		"zan":
			return PackedVector2Array([
				Vector2(0, 0), Vector2(62, 0), Vector2(6, 44), Vector2(66, 44)])
	return PackedVector2Array()

const SKILL_DEFS := [
	{"id": "time", "name": "时·回溯", "fixed": true, "tv": 150.0, "cd": 10.0},
	{"id": "zan", "name": "斩·万象", "fixed": true, "tv": 120.0, "cd": 8.0},
	{"id": "chain", "name": "雷链", "fixed": false, "tv": 100.0, "cd": 6.0},
	{"id": "burn", "name": "灼烧刀痕", "fixed": false, "tv": 110.0, "cd": 12.0},
	{"id": "freeze", "name": "冰冻", "fixed": false, "tv": 130.0, "cd": 15.0},
	{"id": "clone", "name": "分身", "fixed": false, "tv": 140.0, "cd": 12.0},
	{"id": "shield", "name": "时盾", "fixed": false, "tv": 100.0, "cd": 20.0},
	{"id": "blast", "name": "墨爆", "fixed": false, "tv": 120.0, "cd": 8.0},
]

const ZAN_DMG := 30.0
const CHAIN_HOPS := 5
const CHAIN_DMG := 15.0
const CHAIN_RANGE := 220.0
const BURN_SLASHES := 3
const BURN_DPS := 6.0
const BURN_TIME := 3.0
const FREEZE_TIME := 2.0
const CLONE_RATIO := 0.5
const SHIELD_TIME := 5.0
const BLAST_RADIUS := 220.0
const BLAST_DMG := 40.0
const BLAST_PUSH := 120.0

# ============================== §6 怪物 ==============================

const BOMB_DELAY := 0.1
const BOMB_RADIUS := 90.0
const BOMB_DMG := 15.0

# ============================== §8 受击 / 时滞 ==============================

const HIT_CHARGE_PENALTY := 3.0
const HIT_MULT_PENALTY := 0.2
const LAG_TIME := 3.0
const LAG_MAX := 3

# ============================== §9 计分 ==============================

const MULT_BASE := 1.0
const MULT_CAP := 2.0
const MULT_STEP := 0.1
const MULT_STEP_KILLS := 10
const SCORE_REWIND := 1.5
const SCORE_BURST := 2.0
const COMBO_BONUS := 5
const FULL_SCREEN_KILLS := 10
const FULL_SCREEN_BONUS := 200
const RATING_TABLE := [
	[3200, "SS", 2.2], [2000, "S", 1.8], [1200, "A", 1.5], [600, "B", 1.2], [0, "C", 1.0],
]

# ============================== §11 演出 ==============================

const TRAIL_INTERVAL := 0.03
const TRAIL_FADE := 0.4
const FLASH_TIME := 0.1
const KILL_FREEZE := 0.05
const SHAKE_DASH := 2.0
const SHAKE_DASH_TIME := 0.1
const SHAKE_BURST := 8.0
const SHAKE_BURST_TIME := 0.25

const INK := Color("#1A1714")
const RED := Color("#C0392B")
const GREY := Color("#4A443C")

const ENEMY_CFGS := {
	"blob": {"type": "blob", "hp": 10.0, "speed": 60.0, "dmg": 8.0, "radius": 15.0,
		"score": 10, "coin": 1, "tv": 8.0,
		"tex_target": 42.0, "color": Color("#1A1714"), "tex": "res://assets/enemy_blob.png"},
	"fast": {"type": "fast", "hp": 6.0, "speed": 130.0, "dmg": 6.0, "radius": 11.0,
		"score": 15, "coin": 1, "tv": 10.0,
		"tex_target": 38.0, "color": Color("#4A443C"), "tex": "res://assets/enemy_fast.png"},
	"tank": {"type": "tank", "hp": 40.0, "speed": 35.0, "dmg": 15.0, "radius": 27.0,
		"score": 40, "coin": 3, "tv": 25.0,
		"tex_target": 86.0, "color": Color("#1A1714"), "tex": "res://assets/enemy_tank.png"},
	"bomber": {"type": "bomber", "hp": 8.0, "speed": 80.0, "dmg": 10.0, "radius": 13.0,
		"score": 25, "coin": 2, "tv": 12.0,
		"tex_target": 40.0, "color": Color("#8E3B2C"), "tex": "res://assets/enemy_bomber.png"},
	"mite": {"type": "mite", "hp": 8.0, "speed": 115.0, "dmg": 7.0, "radius": 12.0,
		"score": 15, "coin": 1, "tv": 10.0,
		"tex_target": 44.0, "color": Color("#2A2A33"), "tex": "",
		"anim_dir": "res://assets/art/enemies/shadow_mite/"},
	"crystal": {"type": "tank", "hp": 40.0, "speed": 38.0, "dmg": 15.0, "radius": 24.0,
		"score": 45, "coin": 3, "tv": 26.0,
		"tex_target": 80.0, "color": Color("#3D5A80"), "tex": "",
		"anim_dir": "res://assets/art/enemies/crystal_sentinel/animations/",
		"pivot_frac": Vector2(0.5, 0.875)},
}

## §7 时段连续生成表
const WAVE_TABLE := [
	{"t": 5.0, "interval": 0.80, "cap": 12, "mix": {"blob": 1.0}},
	{"t": 12.0, "interval": 0.60, "cap": 18, "mix": {"blob": 0.75, "fast": 0.1, "mite": 0.15}},
	{"t": 20.0, "interval": 0.50, "cap": 24,
		"mix": {"blob": 0.5, "fast": 0.15, "mite": 0.15, "tank": 0.1, "crystal": 0.05, "bomber": 0.05}},
	{"t": 27.0, "interval": 0.40, "cap": 30,
		"mix": {"blob": 0.4, "fast": 0.15, "mite": 0.1, "tank": 0.13, "crystal": 0.12, "bomber": 0.1}},
	{"t": 30.0, "interval": 0.30, "cap": 40,
		"mix": {"blob": 0.3, "fast": 0.2, "mite": 0.1, "tank": 0.13, "crystal": 0.12, "bomber": 0.15}},
]

## §10 局外养成接口（只留数据层，商店 UI 与存档另做）
var upgrades := {
	"ap_regen": 0, "tv_max": 0, "dash_dist": 0, "dash_width": 0,
	"rewind_slots": 0, "rewind_mult": 0, "burst_radius": 0,
	"pointer": 0, "skill_power": 0, "coin_gain": 0, "tv_gain": 0, "ap_cap": 0,
}

var state: State = State.PLAY
var sim_time := 0.0
var run_time := 0.0
var dial_t := 0.0
var ap := float(AP_MAX_BASE)
var last_slash := -99.0
var tv := TV_MAX_BASE
var clock_charge := 0.0
var kills := 0
var score := 0.0
var score_mult := MULT_BASE
var kill_streak := 0
var coins := 0
var sand := 0
var lag_count := 0
var lag_timer := 0.0
var rating := "C"
var payout_coins := 0
var payout_sand := 0
var spawn_timer := 0.0

var ink_path := PackedVector2Array()
var dry_pen := false
var path_alpha := 0.0
var spell_timer := 0.0
var dash_pts := PackedVector2Array()
var dash_i := 0
var dash_d := 0.0
var dash_done := PackedVector2Array()
var dash_stamp := 0
var dash_realtime := false     # 左键表盘斩：不进子弹时间，怪物照常移动
var burst_timer := 0.0
var burst_rewind := false
var combo_kills := 0

var rewind_hist: Array[PackedVector2Array] = []
var rewind_i := 0
var rewind_d := 0.0

var skills: Array = []
var bind_panel := false
var bind_feat := {}
var bind_path := PackedVector2Array()
var burn_charges := 0
var burn_active := false
var shield_t := 0.0
var clones: Array = []
var bolts: Array = []
var blasts: Array = []
var rings: Array = []

var flash_t := 0.0
var hit_flash := 0.0
var hit_stop := 0.0
var announce_t := 0.0
var announce_text := ""
var zan_t := 0.0
var zan_text := "斬"
var zan_red := false
var help_t := 16.0
var shake_t := 0.0
var shake_dur := 1.0
var shake_mag := 0.0

var trail: Array = []
var ghost_trail: Array = []
var particles: Array = []
var numbers: Array = []
var trail_acc := 0.0

var player: Player
var enemies: Array[Enemy] = []
var bleed: BleedCanvas
var bg_layer: PaintLayer
var ink_layer: PaintLayer
var fx_layer: PaintLayer
var hud: HUD
var ink_editor: CanvasLayer
var key_mat: ShaderMaterial
var paper_tex: Texture2D

func _ready() -> void:
	randomize()
	_build_skills()
	var shader: Shader = load("res://shaders/paper_key.gdshader")
	if shader != null:
		key_mat = ShaderMaterial.new()
		key_mat.shader = shader
	if ResourceLoader.exists("res://assets/bg_game_1.png"):
		paper_tex = load("res://assets/bg_game_1.png")
	bg_layer = _make_layer(-100)
	ink_layer = _make_layer(-50)
	fx_layer = _make_layer(50)
	bg_layer.paint = _paint_bg
	ink_layer.paint = _paint_ink
	fx_layer.paint = _paint_fx
	bleed = BleedCanvas.new()
	bleed.z_index = -80
	add_child(bleed)
	player = Player.new()
	player.setup(key_mat)
	player.max_hp = PLAYER_HP
	player.hp = PLAYER_HP
	player.position = ARENA * 0.5
	add_child(player)
	hud = HUD.new()
	hud.game = self
	add_child(hud)

func _make_layer(z: int) -> PaintLayer:
	var l := PaintLayer.new()
	l.z_index = z
	add_child(l)
	return l

func _build_skills() -> void:
	skills.clear()
	for def in SKILL_DEFS:
		var s := {
			"id": def.id, "name": def.name, "fixed": bool(def.fixed),
			"tv": float(def.tv), "cd": float(def.cd), "cd_left": 0.0,
			"dirs": PackedVector2Array(), "turns": -1, "bound": false,
		}
		if bool(def.fixed):
			var feat := _stroke_feature(fixed_stroke(String(def.id)))
			s.dirs = feat.dirs
			s.turns = int(feat.turns)
			s.bound = true
		skills.append(s)

# ============================== 养成公式（§10） ==============================

func tv_max() -> float:
	return minf(TV_MAX_BASE + 50.0 * float(upgrades.tv_max), 750.0)

func tv_regen() -> float:
	return TV_REGEN_BASE

func tv_gain() -> float:
	return 1.0 + 0.1 * float(upgrades.tv_gain)

func coin_gain() -> float:
	return 1.0 + 0.1 * float(upgrades.coin_gain)

func ap_max() -> int:
	return mini(AP_MAX_BASE + int(upgrades.ap_cap), AP_MAX_CAP)

func ap_rate() -> float:
	var r := AP_PER_HOUR / HOUR_PERIOD
	if int(upgrades.pointer) >= 1:
		r += AP_PER_SEC / SEC_PERIOD
	if int(upgrades.pointer) >= 2:
		r += AP_PER_MIN / MIN_PERIOD
	return r * (1.0 + 0.1 * float(upgrades.ap_regen))

func dash_dist() -> float:
	return minf(DASH_DIST_BASE + 20.0 * float(upgrades.dash_dist), DASH_DIST_CAP)

func dash_radius() -> float:
	return DASH_RADIUS + minf(6.0 * float(upgrades.dash_width), 30.0)

func burst_radius() -> float:
	return DASH_RADIUS + minf(15.0 * float(upgrades.burst_radius), 75.0)

func rewind_slots() -> int:
	return mini(REWIND_SLOTS + 2 * int(upgrades.rewind_slots), 15)

func rewind_mult() -> float:
	return minf(REWIND_MULT + 0.1 * float(upgrades.rewind_mult), 1.0)

func skill_power() -> float:
	return 1.0 + 0.15 * float(upgrades.skill_power)

func hour_dir() -> Vector2:
	var ang := -PI * 0.5 + TAU * fmod(dial_t, HOUR_PERIOD) / HOUR_PERIOD
	return Vector2(cos(ang), sin(ang))

func enemy_speed_factor() -> float:
	match state:
		State.PLAY, State.LAG:
			return 1.0
		State.SPELL:
			return BULLET_FACTOR
		State.DASH, State.BURST:
			return 1.0 if dash_realtime else 0.0
		_:
			return 0.0

# ============================== 输入 ==============================

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode in [KEY_F1, KEY_F10]:
		_toggle_editor()
		get_viewport().set_input_as_handled()  # 吞掉本次按键：防同事件派发给新编辑器秒关
		return
	if bind_panel:
		if event is InputEventKey and event.pressed:
			_bind_key(event.keycode)
		return
	if state == State.GAMEOVER:
		var key: bool = event is InputEventKey and event.pressed \
			and event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_R]
		var click: bool = event is InputEventMouseButton and event.pressed
		if key or click:
			get_tree().reload_current_scene()
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if state == State.PLAY:
				_dial_slash()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed and state == State.PLAY:
				_begin_draw()
			elif not event.pressed and state == State.SPELL:
				_end_draw()
	elif event is InputEventKey and event.pressed:
		if event.keycode == KEY_R and state == State.PLAY and clock_charge >= CLOCK_TIME:
			_begin_rewind()
		elif event.keycode == KEY_ESCAPE and state == State.SPELL:
			_cancel_draw()

var _editor_pending := false

func _toggle_editor() -> void:
	if ink_editor != null or _editor_pending:
		return
	# 延迟到本帧输入派发结束后再实例化：否则新建的编辑器会在同一次派发里
	# 收到这个 F1 按下事件并把自己当关闭键 → 瞬开瞬关
	_editor_pending = true
	call_deferred("_open_editor")

func _open_editor() -> void:
	_editor_pending = false
	if ink_editor != null:
		return
	ink_editor = load("res://scenes/ink_editor.tscn").instantiate()
	ink_editor.closed.connect(_on_editor_closed)
	add_child(ink_editor)
	get_tree().paused = true

func _on_editor_closed() -> void:
	ink_editor = null
	get_tree().paused = false
	if state == State.SPELL:
		_cancel_draw()  # 编辑器打开期间松开右键，笔画作废

func _clamped_mouse() -> Vector2:
	var m := get_global_mouse_position()
	return Vector2(
		clampf(m.x, 8.0, ARENA.x - 8.0),
		clampf(m.y, 8.0, ARENA.y - 8.0))

# ============================== 主循环 ==============================

func _process(delta: float) -> void:
	sim_time += delta
	if bind_panel:
		_update_timers(delta)
		_redraw_all()
		return
	if hit_stop > 0.0:
		hit_stop = maxf(hit_stop - delta, 0.0)
		_update_timers(delta)
		_redraw_all()
		return
	var f := enemy_speed_factor()
	if state != State.GAMEOVER:
		run_time = minf(run_time + delta * f, RUN_LIMIT)
	match state:
		State.PLAY:
			_regen(delta, f)
			_update_waves(delta, f)
		State.SPELL:
			_sample_ink()
			_update_spell(delta)
			_regen(delta, f)
			_update_waves(delta, f)
		State.DASH:
			_update_dash(delta)
			if dash_realtime:
				_update_waves(delta, f)
		State.BURST:
			_update_burst(delta)
		State.REWIND:
			_update_rewind(delta)
		State.LAG:
			lag_timer -= delta
			_update_waves(delta, f)
			if lag_timer <= 0.0:
				_end_lag()
		State.GAMEOVER:
			pass
	if state == State.PLAY or state == State.SPELL or state == State.LAG:
		_check_contact()
		_separate()
	_update_status(delta, f)
	if state != State.BURST:
		_update_fx(delta)
	_update_timers(delta)
	if state != State.GAMEOVER and run_time >= RUN_LIMIT:
		_settle()
	_redraw_all()

func _redraw_all() -> void:
	ink_layer.queue_redraw()
	fx_layer.queue_redraw()
	bg_layer.queue_redraw()
	hud.request_redraw()

func _regen(delta: float, f: float) -> void:
	dial_t += delta * f
	ap = minf(ap + ap_rate() * delta * f, float(ap_max()))
	if state == State.PLAY:
		tv = minf(tv + tv_regen() * delta, tv_max())
	if clock_charge < CLOCK_TIME:
		clock_charge = minf(clock_charge + delta * f, CLOCK_TIME)
		if clock_charge >= CLOCK_TIME:
			AudioMgr.play("clock", 1.0, -4.0)

# ============================== §3.2 表盘斩击 ==============================

func _dial_slash() -> void:
	if ap < 1.0 or sim_time - last_slash < SLASH_MIN_GAP:
		return
	ap -= 1.0
	last_slash = sim_time
	var dir := hour_dir()
	var raw := player.position + dir * dash_dist()
	var dst := Vector2(
		clampf(raw.x, 8.0, ARENA.x - 8.0),
		clampf(raw.y, 8.0, ARENA.y - 8.0))
	_begin_dash(PackedVector2Array([player.position, dst]), true)
	_shake(SHAKE_DASH, SHAKE_DASH_TIME)

# ============================== §5 子弹时间书写 ==============================

func _begin_draw() -> void:
	if tv < BULLET_EXIT_TV:
		return
	state = State.SPELL
	dry_pen = false
	path_alpha = 1.0
	spell_timer = 0.0
	ink_path = PackedVector2Array()
	ink_path.append(_clamped_mouse())
	AudioMgr.play("draw", 1.2, -8.0)

func _update_spell(delta: float) -> void:
	spell_timer += delta
	tv = maxf(tv - BULLET_TV_DRAIN * delta, 0.0)
	if tv < BULLET_EXIT_TV and spell_timer >= BULLET_MIN_TIME:
		_end_draw()

func _sample_ink() -> void:
	if ink_path.is_empty() or dry_pen:
		return
	var m := _clamped_mouse()
	var last: Vector2 = ink_path[ink_path.size() - 1]
	var d := m.distance_to(last)
	if d < SAMPLE_DIST:
		return
	var cost := d * TV_COST_PER_PX
	if tv < cost:
		# 墨尽：只画到买得起的位置，笔尖干涸
		var afford := tv / TV_COST_PER_PX
		if afford >= 3.0:
			ink_path.append(last + (m - last).normalized() * afford)
		tv = 0.0
		dry_pen = true
		return
	ink_path.append(m)
	tv -= cost

func _cancel_draw() -> void:
	state = State.PLAY
	ink_path = PackedVector2Array()
	AudioMgr.play("cancel", 1.0, -8.0)

func _end_draw() -> void:
	var path := ink_path
	state = State.PLAY
	if path.size() < 2:
		ink_path = PackedVector2Array()
		return
	var feat := _stroke_feature(path)
	var cast := _try_cast(feat)
	if cast == CAST_TAKEOVER:
		ink_path = PackedVector2Array()
		return
	if cast == CAST_NONE \
			and float(feat.get("px", 0.0)) >= tv_max() * BIND_THRESHOLD and _has_unbound():
		bind_feat = feat
		bind_path = path
		bind_panel = true
		return
	_begin_dash(path)

# ============================== §5.3 咒语识别与绑定 ==============================

func _stroke_feature(path: PackedVector2Array) -> Dictionary:
	if path.size() < 2:
		return {}
	var total := 0.0
	for i in path.size() - 1:
		total += path[i].distance_to(path[i + 1])
	if total < 1.0:
		return {}
	var dirs := PackedVector2Array()
	var prev := _point_along(path, 0.0)
	for i in range(1, SPELL_SAMPLES):
		var p := _point_along(path, float(i) / float(SPELL_SAMPLES - 1))
		var d := p - prev
		dirs.append(d.normalized() if d.length() > 0.001 else Vector2.RIGHT)
		prev = p
	var turns := 0
	for i in range(1, dirs.size()):
		if dirs[i].dot(dirs[i - 1]) < 0.5:
			turns += 1
	return {"dirs": dirs, "turns": turns, "px": total}

func _stroke_match(feat: Dictionary, skill: Dictionary) -> bool:
	if feat.is_empty() or not bool(skill.bound):
		return false
	if float(feat.px) < SPELL_MIN_LEN:
		return false
	if absi(int(feat.turns) - int(skill.turns)) > 1:
		return false
	var a: PackedVector2Array = feat.dirs
	var b: PackedVector2Array = skill.dirs
	if a.size() != b.size() or a.is_empty():
		return false
	var sim := 0.0
	for i in a.size():
		sim += a[i].dot(b[i])
	return sim / float(a.size()) >= SPELL_DIR_SIM

func _has_unbound() -> bool:
	for s in skills:
		if not bool(s.bound):
			return true
	return false

func _bind_key(code: int) -> void:
	if code == KEY_ESCAPE:
		_close_bind()
		return
	var idx := code - KEY_1
	if idx < 0 or idx > 5:
		return
	var s: Dictionary = skills[idx + 2]
	if bool(s.bound):
		return
	s.dirs = bind_feat.dirs
	s.turns = int(bind_feat.turns)
	s.bound = true
	announce_text = "已绑定 · %s" % String(s.name)
	announce_t = 1.6
	AudioMgr.play("clock", 1.1, -4.0)
	_close_bind()

func _close_bind() -> void:
	bind_panel = false
	var path := bind_path
	bind_path = PackedVector2Array()
	bind_feat = {}
	if path.size() >= 2:
		_begin_dash(path)

## 返回值：CAST_NONE 未命中 / CAST_DONE 已释放（斩击照常）/ CAST_TAKEOVER 已释放且接管状态。
func _try_cast(feat: Dictionary) -> int:
	if feat.is_empty():
		return CAST_NONE
	for s in skills:
		if not bool(s.bound) or float(s.cd_left) > 0.0:
			continue
		if float(s.tv) > tv:
			continue
		if not _stroke_match(feat, s):
			continue
		tv = maxf(tv - float(s.tv), 0.0)
		s.cd_left = float(s.cd)
		zan_t = 0.5
		zan_red = true
		zan_text = String(s.name).split("·")[0]
		AudioMgr.play("burst", 1.1, -6.0)
		return CAST_TAKEOVER if _cast(String(s.id)) else CAST_DONE
	return CAST_NONE

func _cast(id: String) -> bool:
	var pw := skill_power()
	match id:
		"time":
			if rewind_hist.is_empty():
				return false
			_begin_rewind()
			return true
		"zan":
			for e in enemies.duplicate():
				_damage(e, ZAN_DMG * pw, true, "normal")
			flash_t = FLASH_TIME
			_shake(SHAKE_BURST, SHAKE_BURST_TIME)
		"chain":
			_cast_chain(pw)
		"burn":
			burn_charges = BURN_SLASHES
		"freeze":
			for e in enemies:
				e.frozen_left = FREEZE_TIME * pw
		"clone":
			if not rewind_hist.is_empty():
				clones.append({
					"path": rewind_hist[rewind_hist.size() - 1], "d": 0.0,
					"pos": player.position, "hit": {}, "pw": pw,
				})
		"shield":
			shield_t = SHIELD_TIME * pw
		"blast":
			_cast_blast(pw)
	return false

func _cast_chain(pw: float) -> void:
	var src := player.position
	var hit := {}
	for _i in CHAIN_HOPS:
		var best: Enemy = null
		var best_d := CHAIN_RANGE
		for e in enemies:
			if e.dead or hit.has(e.get_instance_id()):
				continue
			var d := e.position.distance_to(src)
			if d <= best_d:
				best_d = d
				best = e
		if best == null:
			return
		hit[best.get_instance_id()] = true
		bolts.append({"a": src, "b": best.position, "t": 0.0})
		src = best.position
		_damage(best, CHAIN_DMG * pw, true, "normal")

func _cast_blast(pw: float) -> void:
	rings.append({"pos": player.position, "r": BLAST_RADIUS, "t": 0.0})
	for e in enemies.duplicate():
		if e.dead:
			continue
		var off: Vector2 = e.position - player.position
		if off.length() <= BLAST_RADIUS:
			if off.length() > 1.0:
				e.position += off.normalized() * BLAST_PUSH
			_damage(e, BLAST_DMG * pw, true, "normal")
	_shake(SHAKE_BURST, SHAKE_BURST_TIME)

# ============================== DASH 冲刺 ==============================

func _begin_dash(path: PackedVector2Array, realtime := false) -> void:
	if path.size() < 2:
		state = State.PLAY
		return
	state = State.DASH
	dash_realtime = realtime
	dash_stamp += 1
	ink_path = path
	dash_pts = PackedVector2Array([player.position])
	for p in path:
		if p.distance_to(dash_pts[dash_pts.size() - 1]) > 0.01:
			dash_pts.append(p)
	dash_i = 0
	dash_d = 0.0
	dash_done = PackedVector2Array([path[0]])
	trail.clear()
	trail_acc = TRAIL_INTERVAL
	player.invuln = 999.0
	burn_active = burn_charges > 0
	if burn_active:
		burn_charges -= 1
	AudioMgr.play("dash", 1.0, -4.0)
	# §4 回溯记录：左键 / 右键每一次实际行进轨迹（含出发点）都入栈
	rewind_hist.append(dash_pts.duplicate())
	while rewind_hist.size() > rewind_slots():
		rewind_hist.remove_at(0)
	bleed.stamp(path, false)

func _update_dash(delta: float) -> void:
	var prev := player.position
	var move := DASH_SPEED * delta
	while move > 0.0 and dash_i < dash_pts.size() - 1:
		var a: Vector2 = dash_pts[dash_i]
		var b: Vector2 = dash_pts[dash_i + 1]
		var seg := a.distance_to(b)
		if seg <= 0.001:
			dash_i += 1
			continue
		var remain := seg - dash_d
		if move >= remain:
			move -= remain
			dash_i += 1
			dash_d = 0.0
			player.position = b
		else:
			dash_d += move
			move = 0.0
			player.position = a.lerp(b, dash_d / seg)
	var dir := player.position - prev
	if dir.length() > 0.5:
		player.facing = dir
	_mark_enemies_at(player.position, DASH_DMG)
	if dash_i >= 1 and player.position.distance_to(dash_done[dash_done.size() - 1]) > 0.5:
		dash_done.append(player.position)
	if dash_done.size() > 400:
		dash_done.remove_at(0)
	_spawn_trail(delta)
	if dash_i >= dash_pts.size() - 1:
		_begin_burst(false)

func _mark_enemies_at(pos: Vector2, dmg: float) -> void:
	for e in enemies:
		if e.position.distance_to(pos) <= dash_radius() + float(e.cfg.radius):
			if e.mark_stamp != dash_stamp:
				e.try_mark(sim_time, dash_stamp, dmg)
				if burn_active:
					e.burn_left = BURN_TIME
					e.burn_dps = BURN_DPS * skill_power()
				AudioMgr.play("mark", randf_range(0.95, 1.15), -18.0)

func _spawn_trail(delta: float) -> void:
	trail_acc += delta
	while trail_acc >= TRAIL_INTERVAL:
		trail_acc -= TRAIL_INTERVAL
		trail.append({"pos": player.position, "t": 0.0})

# ============================== BURST 引爆 ==============================

func _begin_burst(is_rewind: bool) -> void:
	state = State.BURST
	burst_timer = BURST_FREEZE
	burst_rewind = is_rewind
	burn_active = false

func _update_burst(delta: float) -> void:
	burst_timer -= delta
	if burst_timer <= 0.0:
		_resolve_burst()

func _resolve_burst() -> void:
	var killed: Array[Enemy] = []
	var hit_pts := PackedVector2Array()
	var marked_ids := {}
	for e in enemies.duplicate():
		if e.dead or not e.is_marked(sim_time):
			continue
		var dmg: float = e.apply_mark()
		marked_ids[e.get_instance_id()] = true
		hit_pts.append(e.position)
		e.hp -= dmg
		numbers.append({
			"pos": e.position + Vector2(0, -float(e.cfg.radius)),
			"val": int(dmg), "red": burst_rewind, "t": 0.0,
		})
		if e.hp <= 0.0:
			killed.append(e)
	# 引爆余波：标记点 burst_radius 内的未标记者吃 50%（对应 §10 引爆范围养成线）
	for p in hit_pts:
		for e in enemies.duplicate():
			if e.dead or marked_ids.has(e.get_instance_id()) or killed.has(e):
				continue
			if e.position.distance_to(p) <= burst_radius() + float(e.cfg.radius):
				marked_ids[e.get_instance_id()] = true
				e.hp -= DASH_DMG * 0.5
				numbers.append({
					"pos": e.position + Vector2(0, -float(e.cfg.radius)),
					"val": int(DASH_DMG * 0.5), "red": burst_rewind, "t": 0.0,
				})
				if e.hp <= 0.0:
					killed.append(e)
	for e in killed:
		_kill_enemy(e, "rewind" if burst_rewind else "burst")
	combo_kills = killed.size()
	if combo_kills >= 2:
		score += float(combo_kills * COMBO_BONUS) * score_mult
	if combo_kills >= FULL_SCREEN_KILLS:
		score += float(FULL_SCREEN_BONUS) * score_mult
	var i := 0
	for e in killed:
		AudioMgr.play_later("kill", i * 0.05, 1.0 + 0.08 * i, -4.0)
		i += 1
	if not killed.is_empty():
		AudioMgr.play("burst", 0.85 if burst_rewind else 1.0, -3.0)
		_shake(SHAKE_BURST, SHAKE_BURST_TIME)
	if combo_kills >= 4:
		flash_t = FLASH_TIME
		zan_t = 0.5
		zan_red = burst_rewind
		zan_text = "斬"
	state = State.PLAY
	player.invuln = POST_DASH_INVULN
	path_alpha = 1.0
	if burst_rewind:
		ghost_trail.clear()

func _damage(e: Enemy, dmg: float, red: bool, source: String) -> void:
	if e == null or e.dead:
		return
	e.hp -= dmg
	numbers.append({
		"pos": e.position + Vector2(0, -float(e.cfg.radius)),
		"val": int(dmg), "red": red, "t": 0.0,
	})
	if e.hp <= 0.0:
		_kill_enemy(e, source)

func _kill_enemy(e: Enemy, source := "normal") -> void:
	if e.dead:
		return
	e.dead = true
	kills += 1
	kill_streak += 1
	if kill_streak % MULT_STEP_KILLS == 0:
		score_mult = minf(score_mult + MULT_STEP, MULT_CAP)
	var m := 1.0
	if source == "rewind":
		m = SCORE_REWIND
	elif source == "burst":
		m = SCORE_BURST
	score += float(e.cfg.score) * m * score_mult
	coins += int(e.cfg.coin)
	tv = minf(tv + float(e.cfg.tv) * tv_gain(), tv_max())
	var type := String(e.cfg.type)
	if (type == "tank" or type == "bomber") and randf() < 0.1:
		sand += 1
	if type == "bomber":
		blasts.append({"pos": e.position, "t": BOMB_DELAY})
	var pos: Vector2 = e.position
	var r: float = float(e.cfg.radius)
	var n := 4 + randi() % 3
	for i in n:
		var ang := randf() * TAU
		var sp := randf_range(60.0, 220.0)
		var col := INK if randf() > 0.25 else RED
		particles.append({
			"pos": pos, "vel": Vector2(cos(ang), sin(ang)) * sp,
			"life": 0.0, "max": randf_range(0.3, 0.55),
			"col": col, "r": randf_range(2.0, 5.0 + r * 0.08),
		})
	enemies.erase(e)
	if e.has_death_anim():
		e.play_death()
	else:
		e.queue_free()
	if state != State.BURST:
		hit_stop = maxf(hit_stop, KILL_FREEZE)

# ============================== §6 爆裂连锁 ==============================

func _update_blasts(delta: float) -> void:
	if blasts.is_empty():
		return
	var fired: Array = []
	for b in blasts:
		b.t -= delta
		if b.t <= 0.0:
			fired.append(b)
	blasts = blasts.filter(func(x): return x.t > 0.0)
	for b in fired:
		_blast_at(b.pos)

func _blast_at(pos: Vector2) -> void:
	rings.append({"pos": pos, "r": BOMB_RADIUS, "t": 0.0})
	AudioMgr.play("burst", 1.25, -8.0)
	for e in enemies.duplicate():
		if e.dead:
			continue
		if e.position.distance_to(pos) <= BOMB_RADIUS + float(e.cfg.radius):
			_damage(e, BOMB_DMG, true, "normal")
	for i in 5:
		var ang := randf() * TAU
		particles.append({
			"pos": pos, "vel": Vector2(cos(ang), sin(ang)) * randf_range(120.0, 320.0),
			"life": 0.0, "max": randf_range(0.25, 0.5), "col": RED, "r": randf_range(3.0, 7.0),
		})

# ============================== 持续状态：灼烧 / 冰冻 / 分身 ==============================

func _update_status(delta: float, f: float) -> void:
	if shield_t > 0.0:
		shield_t = maxf(shield_t - delta, 0.0)
	for s in skills:
		if float(s.cd_left) > 0.0:
			s.cd_left = maxf(float(s.cd_left) - delta, 0.0)
	for e in enemies.duplicate():
		if e.dead:
			continue
		if e.frozen_left > 0.0:
			e.frozen_left = maxf(e.frozen_left - delta * f, 0.0)
		if e.burn_left > 0.0:
			e.burn_left = maxf(e.burn_left - delta * f, 0.0)
			e.hp -= e.burn_dps * delta * f
			if e.hp <= 0.0:
				_kill_enemy(e, "normal")
	_update_blasts(delta)
	_update_clones(delta)

func _update_clones(delta: float) -> void:
	if clones.is_empty():
		return
	for c in clones:
		c.d += delta / REWIND_PATH_TIME
		var pos: Vector2 = _point_along(c.path, clampf(c.d, 0.0, 1.0))
		c.pos = pos
		for e in enemies.duplicate():
			if e.dead or c.hit.has(e.get_instance_id()):
				continue
			if e.position.distance_to(pos) <= dash_radius() + float(e.cfg.radius):
				c.hit[e.get_instance_id()] = true
				_damage(e, DASH_DMG * CLONE_RATIO * float(c.pw), true, "normal")
	clones = clones.filter(func(x): return x.d < 1.0)

# ============================== REWIND 回溯 ==============================

func _begin_rewind() -> void:
	if rewind_hist.is_empty():
		return
	state = State.REWIND
	dash_realtime = false
	clock_charge = 0.0
	rewind_i = rewind_hist.size() - 1   # 由最近一段倒着走回最早一段的起点
	rewind_d = 0.0
	ghost_trail.clear()
	trail.clear()
	trail_acc = TRAIL_INTERVAL
	player.invuln = 999.0
	zan_t = 0.5
	zan_red = true
	zan_text = "回溯"
	AudioMgr.play("rewind", 1.0, -2.0)

func _update_rewind(delta: float) -> void:
	if rewind_i < 0 or rewind_i >= rewind_hist.size():
		_begin_burst(true)
		return
	if rewind_d == 0.0:
		dash_stamp += 1
		bleed.stamp(rewind_hist[rewind_i], true)
	var path: PackedVector2Array = rewind_hist[rewind_i]
	var prev := player.position
	rewind_d += delta / REWIND_PATH_TIME
	var pos := _point_along(path, 1.0 - clampf(rewind_d, 0.0, 1.0))
	player.position = pos
	var dir := pos - prev
	if dir.length() > 0.5:
		player.facing = dir
	# 单帧位移可能很长：沿途补采样，避免漏掉路径中间的怪
	var span := prev.distance_to(pos)
	var steps := maxi(1, int(ceil(span / SAMPLE_DIST)))
	for i in range(1, steps + 1):
		_mark_enemies_at(prev.lerp(pos, float(i) / float(steps)), DASH_DMG * rewind_mult())
	ghost_trail.append({"pos": pos, "t": 0.0})
	if ghost_trail.size() > 240:
		ghost_trail.pop_front()
	_spawn_trail(delta)
	if rewind_d >= 1.0:
		rewind_i -= 1
		rewind_d = 0.0

func _point_along(path: PackedVector2Array, t: float) -> Vector2:
	if path.size() == 0:
		return player.position
	if path.size() == 1:
		return path[0]
	var total := 0.0
	for i in path.size() - 1:
		total += path[i].distance_to(path[i + 1])
	if total <= 0.0:
		return path[0]
	var target := total * t
	var acc := 0.0
	for i in path.size() - 1:
		var seg := path[i].distance_to(path[i + 1])
		if seg <= 0.0:
			continue
		if acc + seg >= target:
			return path[i].lerp(path[i + 1], (target - acc) / seg)
		acc += seg
	return path[path.size() - 1]

# ============================== §8 受击 / 时滞 ==============================

func _check_contact() -> void:
	if player.invuln > 0.0 or shield_t > 0.0:
		return
	for e in enemies:
		if e.dead or e.spawn_left > 0.0:
			continue
		if e.position.distance_to(player.position) <= float(e.cfg.radius) + Player.RADIUS:
			if player.take_hit(float(e.cfg.dmg)):
				hit_flash = 0.25
				AudioMgr.play("hit", 0.9, -2.0)
				clock_charge = maxf(clock_charge - HIT_CHARGE_PENALTY, 0.0)
				score_mult = maxf(score_mult - HIT_MULT_PENALTY, MULT_BASE)
				kill_streak = 0
				var away := (e.position - player.position).normalized()
				e.position += away * 26.0
			if player.hp <= 0.0:
				_enter_lag()
			return

func _enter_lag() -> void:
	lag_count += 1
	if lag_count > LAG_MAX:
		_settle()
		return
	state = State.LAG
	lag_timer = LAG_TIME
	ap = 0.0
	ink_path = PackedVector2Array()
	player.invuln = LAG_TIME + 0.5
	zan_t = 0.6
	zan_red = true
	zan_text = "时滞"
	AudioMgr.play("over", 1.2, -6.0)

func _end_lag() -> void:
	player.hp = player.max_hp
	player.invuln = 0.6
	state = State.PLAY

# ============================== §9 结算 ==============================

func _settle() -> void:
	state = State.GAMEOVER
	ink_path = PackedVector2Array()
	var total := int(round(score))
	var rmul := 1.0
	for row in RATING_TABLE:
		if total >= int(row[0]):
			rating = String(row[1])
			rmul = float(row[2])
			break
	payout_coins = int(round((float(coins) + 20.0) * rmul * coin_gain()))
	payout_sand = sand
	AudioMgr.play("over", 1.0, 0.0)

func rating_mult() -> float:
	for row in RATING_TABLE:
		if int(round(score)) >= int(row[0]):
			return float(row[2])
	return 1.0

# ============================== §7 波次 ==============================

func _wave_seg() -> Dictionary:
	for w in WAVE_TABLE:
		if run_time < float(w.t):
			return w
	return WAVE_TABLE[WAVE_TABLE.size() - 1]

func _update_waves(delta: float, factor: float) -> void:
	if run_time >= RUN_LIMIT:
		return
	var seg := _wave_seg()
	spawn_timer -= delta * factor
	if spawn_timer <= 0.0:
		spawn_timer = float(seg.interval)
		if enemies.size() < mini(int(seg.cap), MAX_ENEMIES):
			_spawn_enemy(seg.mix)

func _spawn_enemy(mix: Dictionary) -> void:
	var roll := randf()
	var acc := 0.0
	var type := "blob"
	for k in mix:
		acc += float(mix[k])
		if roll <= acc:
			type = String(k)
			break
	var e := Enemy.new()
	e.position = _edge_pos()
	e.setup(ENEMY_CFGS[type].duplicate(), self, key_mat)
	add_child(e)
	enemies.append(e)

func _edge_pos() -> Vector2:
	var m := SPAWN_MARGIN
	match randi() % 4:
		0:
			return Vector2(randf_range(m, ARENA.x - m), m)
		1:
			return Vector2(ARENA.x - m, randf_range(m, ARENA.y - m))
		2:
			return Vector2(randf_range(m, ARENA.x - m), ARENA.y - m)
		_:
			return Vector2(m, randf_range(m, ARENA.y - m))

func _separate() -> void:
	for i in enemies.size():
		var a := enemies[i]
		for j in range(i + 1, enemies.size()):
			var b := enemies[j]
			var d := a.position.distance_to(b.position)
			var min_d := float(a.cfg.radius) + float(b.cfg.radius)
			if d < min_d and d > 0.01:
				var push := (a.position - b.position) / d * (min_d - d) * 0.5
				a.position += push
				b.position -= push

# ============================== 特效计时 ==============================

func _shake(mag: float, dur: float) -> void:
	shake_mag = maxf(shake_mag, mag)
	shake_t = maxf(shake_t, dur)
	shake_dur = maxf(shake_t, 0.01)

func _update_fx(delta: float) -> void:
	for t in trail:
		t.t += delta
	trail = trail.filter(func(x): return x.t < TRAIL_FADE)
	for g in ghost_trail:
		g.t += delta
	ghost_trail = ghost_trail.filter(func(x): return x.t < TRAIL_FADE)
	for p in particles:
		p.life += delta
		p.pos += p.vel * delta
		p.vel *= maxf(0.0, 1.0 - 3.0 * delta)
	particles = particles.filter(func(x): return x.life < x.max)
	for n in numbers:
		n.t += delta
	numbers = numbers.filter(func(x): return x.t < 0.8)
	for b in bolts:
		b.t += delta
	bolts = bolts.filter(func(x): return x.t < 0.25)
	for r in rings:
		r.t += delta
	rings = rings.filter(func(x): return x.t < 0.35)

func _update_timers(delta: float) -> void:
	if flash_t > 0.0:
		flash_t = maxf(flash_t - delta, 0.0)
	if hit_flash > 0.0:
		hit_flash = maxf(hit_flash - delta, 0.0)
	if announce_t > 0.0:
		announce_t = maxf(announce_t - delta, 0.0)
	if zan_t > 0.0:
		zan_t = maxf(zan_t - delta, 0.0)
	if help_t > 0.0:
		help_t = maxf(help_t - delta, 0.0)
	if state == State.PLAY and path_alpha > 0.0:
		path_alpha = maxf(path_alpha - delta * 2.2, 0.0)
	if shake_t > 0.0:
		shake_t = maxf(shake_t - delta, 0.0)
		var k := shake_t / shake_dur
		position = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * shake_mag * k
		if shake_t <= 0.0:
			shake_mag = 0.0
			position = Vector2.ZERO

# ============================== 绘制 ==============================

func _paint_bg(l: PaintLayer) -> void:
	if paper_tex != null:
		l.draw_texture_rect(paper_tex, Rect2(Vector2.ZERO, ARENA), false)
	else:
		l.draw_rect(Rect2(Vector2.ZERO, ARENA), Color("#F5F1E8"))
		# 円相：背景一枚巨大淡墨圆
		l.draw_arc(ARENA * 0.5, 235.0, 0.0, TAU, 96, Color(0.1, 0.09, 0.08, 0.06), 28.0)
		l.draw_arc(ARENA * 0.5, 235.0, 0.0, TAU, 96, Color(0.1, 0.09, 0.08, 0.04), 52.0)

func _paint_ink(l: PaintLayer) -> void:
	# 墨迹：毛笔枯笔飞白（样式参数来自 InkStyle.current，编辑器可实时改）
	if ink_path.size() >= 2:
		var alpha := 0.85
		if state == State.PLAY:
			alpha = 0.85 * path_alpha
		InkRenderer.draw_brush_path(l, ink_path, alpha, false)
	if state == State.DASH or state == State.BURST:
		InkRenderer.draw_brush_path(l, dash_done, 0.95, false)
	if state == State.REWIND:
		for path in rewind_hist:
			if path.size() >= 2:
				InkRenderer.draw_brush_path(l, path, 0.6, true)

func _paint_fx(l: PaintLayer) -> void:
	for t in trail:
		var k: float = 1.0 - t.t / TRAIL_FADE
		_draw_silhouette(l, t.pos, k * 0.4, INK)
	for g in ghost_trail:
		var k2: float = 1.0 - g.t / TRAIL_FADE
		_draw_silhouette(l, g.pos, k2 * 0.55, RED)
	for c in clones:
		_draw_silhouette(l, c.pos, 0.5, RED)
	for p in particles:
		var k3: float = 1.0 - p.life / p.max
		var c2: Color = p.col
		l.draw_circle(p.pos, float(p.r) * (0.5 + 0.5 * k3),
			Color(c2.r, c2.g, c2.b, clampf(k3, 0.0, 1.0)))
	for b in bolts:
		var ba: float = clampf(1.0 - b.t / 0.25, 0.0, 1.0)
		l.draw_line(b.a, b.b, Color(RED.r, RED.g, RED.b, ba), 3.0)
	for r in rings:
		var ra: float = clampf(1.0 - r.t / 0.35, 0.0, 1.0)
		l.draw_arc(r.pos, float(r.r) * (0.4 + 0.6 * (1.0 - ra)), 0.0, TAU, 48,
			Color(RED.r, RED.g, RED.b, ra * 0.7), 3.0)
	# 被标记怪：红痕 + 红环
	for e in enemies:
		if e.is_marked(sim_time):
			var r2: float = float(e.cfg.radius) + 8.0
			var c3 := Color(RED.r, RED.g, RED.b, 0.9)
			var dir := Vector2(0.8, 0.6)
			l.draw_line(e.position + dir * r2, e.position - dir * r2, c3, 3.0)
			var dir2 := Vector2(-0.6, 0.55)
			l.draw_line(e.position + dir2 * r2 * 0.9, e.position - dir2 * r2 * 0.9, c3, 2.0)
			l.draw_arc(e.position, r2 + 5.0, 0.0, TAU, 24,
				Color(RED.r, RED.g, RED.b, 0.35), 1.5)
		if e.frozen_left > 0.0:
			l.draw_arc(e.position, float(e.cfg.radius) + 5.0, 0.0, TAU, 20,
				Color(0.35, 0.5, 0.62, 0.75), 2.0)
		if e.burn_left > 0.0:
			l.draw_arc(e.position, float(e.cfg.radius) + 3.0, 0.0, TAU, 16,
				Color(0.78, 0.35, 0.16, 0.7), 2.0)
	_paint_dial(l)

## §11 地面表盘 + 头顶 AP 点（世界内 UI，不进 HUD）
func _paint_dial(l: PaintLayer) -> void:
	if state == State.GAMEOVER or player == null:
		return
	var c := player.position
	l.draw_arc(c, DIAL_RADIUS, 0.0, TAU, 48, Color(GREY.r, GREY.g, GREY.b, 0.30), 1.5)
	for i in 12:
		var a := -PI * 0.5 + TAU * float(i) / 12.0
		var d := Vector2(cos(a), sin(a))
		l.draw_line(c + d * (DIAL_RADIUS - 5.0), c + d * DIAL_RADIUS,
			Color(GREY.r, GREY.g, GREY.b, 0.28), 1.0)
	if int(upgrades.pointer) >= 1:
		var sa := -PI * 0.5 + TAU * fmod(dial_t, SEC_PERIOD) / SEC_PERIOD
		l.draw_line(c, c + Vector2(cos(sa), sin(sa)) * (DIAL_RADIUS - 2.0),
			Color(GREY.r, GREY.g, GREY.b, 0.5), 2.0)
	if int(upgrades.pointer) >= 2:
		var ma := -PI * 0.5 + TAU * fmod(dial_t, MIN_PERIOD) / MIN_PERIOD
		l.draw_line(c, c + Vector2(cos(ma), sin(ma)) * (DIAL_RADIUS - 8.0),
			Color(GREY.r, GREY.g, GREY.b, 0.5), 2.0)
	# 时针（唯一锚定斩击方向，粗 4 px）
	var ready := ap >= 1.0
	var hcol := Color(INK.r, INK.g, INK.b, 0.9) if ready else Color(GREY.r, GREY.g, GREY.b, 0.45)
	l.draw_line(c, c + hour_dir() * (DIAL_RADIUS - 2.0), hcol, 4.0)
	if ready:
		l.draw_line(c + hour_dir() * DIAL_RADIUS, c + hour_dir() * (DIAL_RADIUS + 12.0),
			Color(RED.r, RED.g, RED.b, 0.55), 2.0)
	l.draw_circle(c, 3.0, hcol)
	# 头顶 AP 点
	var n := ap_max()
	var full := int(floor(ap))
	var w := 12.0 * float(n - 1)
	for i in n:
		var p := c + Vector2(-w * 0.5 + 12.0 * float(i), -34.0)
		if i < full:
			l.draw_circle(p, 4.0, Color(INK.r, INK.g, INK.b, 0.9))
		else:
			l.draw_arc(p, 4.0, 0.0, TAU, 12, Color(GREY.r, GREY.g, GREY.b, 0.5), 1.0)
	if shield_t > 0.0:
		l.draw_arc(c, DIAL_RADIUS + 8.0, 0.0, TAU, 40,
			Color(RED.r, RED.g, RED.b, 0.35 + 0.2 * sin(sim_time * 8.0)), 3.0)

func _draw_silhouette(l: PaintLayer, pos: Vector2, alpha: float, col: Color) -> void:
	var c := Color(col.r, col.g, col.b, alpha)
	l.draw_circle(pos, 9.0, c)
	var pts := PackedVector2Array([
		pos + Vector2(-11, 13), pos + Vector2(0, -14), pos + Vector2(11, 13),
	])
	l.draw_colored_polygon(pts, c)
