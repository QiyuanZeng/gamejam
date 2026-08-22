class_name Game
extends Node2D
## 《时间刺客》主控制器 —— 表盘 AP 斩击 + 子弹时间咒语 + 回溯引爆。
## 左键：沿时针指向固定距离斩击（消耗 1 AP，方案 A）。
## 右键：按住进子弹时间书写（扣 TV），松开沿笔画斩击；笔画匹配咒语则附加释放技能。
## 伤害沿用「标记—引爆」模型：掠过只挂标记，终点顿帧统一结算。

enum State { PLAY, SPELL, DASH, BURST, REWIND, LAG, GAMEOVER }

# ============================== §1 全局 ==============================

const ARENA := Vector2(3000.0, 3000.0)
const PLAYER_HP := 100.0

## 刷怪全局参数已搬到 res://data/balance.tres（BalanceConfig），_ready 里读进来。
var max_enemies := 130
var spawn_margin := 26.0

## 相机死区跟随（移植 proto/clock-swing）：死区内不动，超出 lerp 跟随，超出安全距离强制 snap
const CAM_DEADZONE := 150.0
const CAM_SAFE := 400.0
const CAM_LERP := 15.0

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
const DIAL_RADIUS := 70.0

const DASH_SPEED := 3200.0
const DASH_RADIUS := 140.0
const DASH_DMG := 20.0
const DASH_DIST_BASE := 520.0
const DASH_DIST_CAP := 800.0
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
const BIND_ENERGY_RATIO := 0.70   # 点亮空碑的门槛：单笔要烧掉起笔时余额的这么多（含子弹流逝）
const BIND_CHANCE := 0.50         # 达标后的触发概率（策划案原定 20%，实测太闷，提到一半）
## 笔形识别（算法、阈值、神纹录）全部收在 SpellMatch，本文件直调，不做别名转发。
## 释放不再另收墨钱 —— 时间之力只花在「描绘路径」上，画出来即生效。

## _try_cast 结果：未命中 / 已释放（斩击照常）/ 已释放且接管状态（如「时」直接进回溯）
const CAST_NONE := 0
const CAST_DONE := 1
const CAST_TAKEOVER := 2

# —— 七道神纹的效果参数 ——
const THUNDER_BOLTS := 6          # 雷霆万钧：随机选中的落雷目标数
const THUNDER_DMG := 20.0
const THUNDER_RADIUS := 82.0      # 每道雷的溅射半径
const QUAKE_WAVES := 6            # 山崩地裂：6 轮地震，跟着人物走
const QUAKE_GAP := 0.5
const QUAKE_RADIUS := 155.0
const QUAKE_DMG := 12.0
const ENT_COUNT := 4              # 妖木精灵：4 个树人自由攻击
const ENT_LIFE := 12.0
const ENT_SPEED := 155.0
const ENT_REACH := 44.0
const ENT_DMG := 10.0
const ENT_GAP := 0.7
const FLOOD_DIRS := 8             # 水漫金山：八向水浪
const FLOOD_SPEED := 540.0
const FLOOD_RANGE := 640.0
const FLOOD_WIDTH := 34.0
const FLOOD_DMG := 16.0
const DOMAIN_TIME := 6.0          # 时间领域：原地驻留，持续伤害 + 回溯加速充能
const DOMAIN_RADIUS := 195.0
const DOMAIN_DPS := 14.0
const DOMAIN_CHARGE := 2.0        # 站在领域内时钟表额外充能的倍率
const SWORD_INNER := 6            # 无限剑阵：内外两圈落剑
const SWORD_OUTER := 12
const SWORD_R_IN := 115.0
const SWORD_R_OUT := 245.0
const SWORD_FALL := 0.4           # 单剑下落时间
const SWORD_RADIUS := 58.0
const SWORD_DMG := 22.0
const ALPHA_HITS := 8             # 阿尔法突袭：消失期间的多段斩次数
const ALPHA_GAP := 0.1
const ALPHA_RADIUS := 265.0
const ALPHA_DMG := 12.0

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

## 怪物数值、刷怪波表、刷怪全局参数统一收在 res://data/balance.tres（BalanceConfig），
## 由 EnemyDB 按 id、WaveDB 按 until_time 取用。改数值 / 换模型 / 调刷怪节奏都在编辑器里
## 双击那份总表改，本文件不再存表。详见 docs/enemies.md。

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
var bind_chance := BIND_CHANCE     # 觉醒概率的运行时钩子：调参与测试改这个，常量留作策划基准
## 觉醒时是否停下来让玩家挑碑。默认关 —— 触发即随机点亮一块空碑并当场施展，不打断战斗。
## 打开则弹面板（战局定格，按 1~N 选碑、Esc 放弃）。
var bind_pick_panel := false
var bind_panel := false            # 觉醒选碑面板：开着时战局暂停，只收 1~6 与 Esc
var bind_feat := {}                # 待刻上碑的笔形特征
var bind_path := PackedVector2Array()   # 欠着的那一笔轨迹，选完碑再补斩击

var ink_path := PackedVector2Array()
var ink_ages := PackedFloat32Array()   # 与 ink_path 逐点对齐的年龄（秒），水痕按它老化
var dry_pen := false
var draw_tv0 := 0.0            # 起笔时的时间之力余额，觉醒门槛拿它当分母
var path_alpha := 0.0
var spell_timer := 0.0
var dash_pts := PackedVector2Array()
var dash_i := 0
var dash_d := 0.0
var dash_done := PackedVector2Array()
var dash_ages := PackedFloat32Array()  # 与 dash_done 逐点对齐的年龄（秒）
var dash_stamp := 0
var dash_realtime := false     # 左键表盘斩：不进子弹时间，怪物照常移动
var burst_timer := 0.0
var burst_rewind := false
var combo_kills := 0

var rewind_hist: Array[PackedVector2Array] = []
var rewind_i := 0
var rewind_d := 0.0

var skills: Array = []
var bolts: Array = []             # 雷霆万钧的电弧（纯演出）
var blasts: Array = []            # 爆魈死亡连锁的待爆点
var rings: Array = []             # 圆形冲击波（爆炸 / 落雷 / 地震 / 落剑共用）
var quakes: Array = []            # 山崩地裂：{left, next} 跟随玩家
var ents: Array = []              # 妖木精灵：{pos, life, cd, pw}
var floods: Array = []            # 水漫金山：{org, dir, d, hit, pw}
var domains: Array = []           # 时间领域：{pos, left, pw}
var swords: Array = []            # 无限剑阵：{pos, t, pw}
var alpha_left := 0               # 阿尔法突袭：剩余斩击段数
var alpha_gap := 0.0
var enemy_bullets: Array = []     # 远程小兵普攻弹：{pos, dir, spd, dmg, r, life, col}

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
var spell_lab: CanvasLayer
var key_mat: ShaderMaterial
var paper_tex: Texture2D
var surface_phase := 0.0       # 水面底纹流动相位，同编辑器 InkEditor.surface_phase
var camera: Camera2D
var dial_pointer: Sprite2D
const DIAL_POINTER_PIVOT_FRAC := Vector2(0.0134, 0.4988)
const DIAL_POINTER_SRC_LEN := 692.6
const DIAL_POINTER_LEN := 110.0

func _ready() -> void:
	randomize()
	var bal := BalanceConfig.get_config()
	max_enemies = bal.max_enemies
	spawn_margin = bal.spawn_margin
	_build_skills()
	var shader: Shader = load("res://shaders/paper_key.gdshader")
	if shader != null:
		key_mat = ShaderMaterial.new()
		key_mat.shader = shader
	if ResourceLoader.exists("res://assets/bg_shuimian.png"):
		paper_tex = load("res://assets/bg_shuimian.png")
	elif ResourceLoader.exists("res://assets/bg_game_main.png"):
		paper_tex = load("res://assets/bg_game_main.png")
	bg_layer = _make_layer(-100)
	bg_layer.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	ink_layer = _make_layer(-50)
	fx_layer = _make_layer(50)
	bg_layer.paint = _paint_bg
	ink_layer.paint = _paint_ink
	fx_layer.paint = _paint_fx
	# 渗墨拓印层已停用：F1 编辑器里没有这层，留着会让局内水痕多一层残留而对不上
	player = Player.new()
	player.setup(key_mat)
	player.max_hp = PLAYER_HP
	player.hp = PLAYER_HP
	player.position = ARENA * 0.5
	add_child(player)
	camera = Camera2D.new()
	camera.position = player.position
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(ARENA.x)
	camera.limit_bottom = int(ARENA.y)
	add_child(camera)
	camera.make_current()
	if ResourceLoader.exists("res://assets/art/effects/dial_pointer.png"):
		dial_pointer = Sprite2D.new()
		dial_pointer.texture = load("res://assets/art/effects/dial_pointer.png")
		dial_pointer.centered = false
		var tex_size := dial_pointer.texture.get_size()
		dial_pointer.offset = -DIAL_POINTER_PIVOT_FRAC * tex_size
		var s := DIAL_POINTER_LEN / DIAL_POINTER_SRC_LEN
		dial_pointer.scale = Vector2(s, s)
		dial_pointer.z_index = 60
		add_child(dial_pointer)
	hud = HUD.new()
	hud.game = self
	add_child(hud)

func _make_layer(z: int) -> PaintLayer:
	var l := PaintLayer.new()
	l.z_index = z
	add_child(l)
	return l

func _build_skills() -> void:
	skills = SpellMatch.build_skills()

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
	if event is InputEventKey and event.pressed and event.keycode == KEY_F2:
		_toggle_lab()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_F3:
		_refill_tv()
		get_viewport().set_input_as_handled()
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

var _lab_pending := false

func _toggle_lab() -> void:
	if spell_lab != null or _lab_pending:
		return
	_lab_pending = true
	call_deferred("_open_lab")

func _open_lab() -> void:
	_lab_pending = false
	if spell_lab != null:
		return
	spell_lab = load("res://scenes/spell_lab.tscn").instantiate()
	spell_lab.game = self
	spell_lab.closed.connect(_on_lab_closed)
	add_child(spell_lab)
	get_tree().paused = true

func _on_lab_closed() -> void:
	spell_lab = null
	get_tree().paused = false
	if state == State.SPELL:
		_cancel_draw()

## F3 测试用：时间之力一键回满。写到一半按也认 —— 连带把起笔余额重记，
## 否则「烧掉起笔余额七成」的账会算成负数，觉醒反而再也过不了闸。
func _refill_tv() -> void:
	tv = tv_max()
	dry_pen = false
	if state == State.SPELL:
		draw_tv0 = tv
	announce_text = "时间之力已回满"
	announce_t = 1.2
	AudioMgr.play("clock", 1.2, -6.0)

func _clamped_mouse() -> Vector2:
	var m := get_global_mouse_position()
	return Vector2(
		clampf(m.x, 8.0, ARENA.x - 8.0),
		clampf(m.y, 8.0, ARENA.y - 8.0))

# ============================== 主循环 ==============================

func _process(delta: float) -> void:
	sim_time += delta
	if bind_panel:
		# 选碑期间战局定格：只跑计时与重绘，怪不动、时间不流逝
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
		# 本局没有时限：run_time 只作为「已持续多久」的统计量与波表推进依据
		run_time += delta * f
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
	# 本局不再有时间结算：唯一的结束条件是体力（时滞次数）耗尽，见 _enter_lag()
	_update_camera(delta)
	_redraw_all()

func _update_camera(delta: float) -> void:
	if camera == null or player == null:
		return
	# 死区跟随：玩家在死区内相机不动（有位移感），超出 lerp 跟随；超安全距离强制 snap 防出框
	var offset := player.position - camera.position
	var dist := offset.length()
	if dist > CAM_SAFE:
		camera.position = player.position - offset.normalized() * CAM_SAFE
	elif dist > CAM_DEADZONE:
		camera.position = camera.position.lerp(player.position, minf(1.0, delta * CAM_LERP))

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
	draw_tv0 = tv          # 记下起笔时的家底：觉醒门槛按「这一笔烧掉手头的几成」算
	path_alpha = 1.0
	spell_timer = 0.0
	ink_path = PackedVector2Array()
	ink_path.append(_clamped_mouse())
	ink_ages = PackedFloat32Array([0.0])
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
			ink_ages.append(0.0)
		tv = 0.0
		dry_pen = true
		return
	ink_path.append(m)
	ink_ages.append(0.0)
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
	var feat := SpellMatch.feature(path)
	# 一次比对定全局：命中就放最像的那道；没命中且这笔够长够独特，才轮到点亮空碑
	var hit := SpellMatch.best_match(feat, skills)
	if int(hit.i) >= 0:
		if _fire(skills[int(hit.i)]) == CAST_TAKEOVER:
			ink_path = PackedVector2Array()
			return
		_begin_dash(path)
		return
	if _try_awaken(feat, float(hit.top), path):
		return                    # 选碑面板已弹出，斩击等玩家选完再走
	_begin_dash(path)

# ============================== §5.3 神纹判定与激活 ==============================

## 命中已激活的神纹 → 直接释放。释放本身不收墨钱，只走冷却。
## 返回 CAST_DONE（斩击照常）/ CAST_TAKEOVER（如「时」直接接管进回溯）。
func _fire(s: Dictionary) -> int:
	s.cd_left = float(s.cd)
	zan_t = 0.5
	zan_red = true
	zan_text = String(s.name).split("·")[0]
	AudioMgr.play("burst", 1.1, -6.0)
	return CAST_TAKEOVER if _cast(String(s.id)) else CAST_DONE

## 神纹录里还空着的碑位下标，按表内顺序。面板的 1~N 就是照这个列表点名的。
func blank_slots() -> Array:
	var out: Array = []
	for i in skills.size():
		if not bool(skills[i].bound):
			out.append(i)
	return out

## 尝试点亮空碑。五道闸全过才算觉醒：
##   ① 这一笔够长（至少够得着识别门槛），不然墨快空时随手一点也算觉醒；
##   ② 这一笔烧掉起笔时手头时间之力的 BIND_ENERGY_RATIO 以上；
##   ③ 没命中任何已激活的神纹（调用方保证）；
##   ④ 跟已激活的神纹都不像（最高相似度 top < BIND_MAX_SIM）；
##   ⑤ 掷骰过 bind_chance。
## 闸 ② 的分母是**起笔时的余额**而不是 tv_max：墨本来就没满时，玩家画到笔干也
## 凑不满上限的七成，按上限卡等于「TV 不满就永远不可能觉醒」。
## 过闸后按 bind_pick_panel 分岔：默认随机挑一块空碑直接绑；开了开关才停下来让玩家选。
func _try_awaken(feat: Dictionary, top: float, path: PackedVector2Array) -> bool:
	if feat.is_empty() or float(feat.get("px", 0.0)) < SpellMatch.MIN_LEN:
		return false
	if draw_tv0 - tv < draw_tv0 * BIND_ENERGY_RATIO:
		return false
	if top >= SpellMatch.BIND_MAX_SIM:
		return false
	var blank := blank_slots()
	if blank.is_empty() or randf() >= bind_chance:
		return false
	bind_feat = feat
	bind_path = path
	AudioMgr.play("clock", 1.1, -4.0)
	if bind_pick_panel:
		bind_panel = true
		return true
	_bind_slot(int(blank[randi() % blank.size()]))
	return true

## 面板选碑：1~N 对应 blank_slots() 的第几块空碑，Esc 放弃。
func _bind_key(code: int) -> void:
	if code == KEY_ESCAPE:
		_close_bind()
		return
	var idx := code - KEY_1
	var blank := blank_slots()
	if idx < 0 or idx >= blank.size():
		return
	_bind_slot(int(blank[idx]))

## 把待绑的笔形刻上第 i 块碑，并当场把该技能放出来 —— 觉醒那一笔本身就是一次施法。
func _bind_slot(i: int) -> void:
	var s: Dictionary = skills[i]
	s.cloud = bind_feat.cloud
	s.bound = true
	announce_text = "神纹觉醒 · %s" % String(s.name)
	announce_t = 1.8
	_close_bind(_fire(s) == CAST_TAKEOVER)

## 关盘并把欠着的那次斩击补上（除非刚才的技能已经接管了状态，比如「时」进回溯）。
func _close_bind(takeover := false) -> void:
	bind_panel = false
	var path := bind_path
	bind_path = PackedVector2Array()
	bind_feat = {}
	ink_path = PackedVector2Array()
	if not takeover and path.size() >= 2:
		_begin_dash(path)

func _cast(id: String) -> bool:
	var pw := skill_power()
	match id:
		"time":
			if rewind_hist.is_empty():
				return false
			_begin_rewind()
			return true
		"thunder":
			_cast_thunder(pw)
		"quake":
			quakes.append({"left": QUAKE_WAVES, "next": 0.0, "pw": pw})
		"ent":
			for i in ENT_COUNT:
				var a := TAU * float(i) / float(ENT_COUNT) + randf()
				ents.append({
					"pos": player.position + Vector2(cos(a), sin(a)) * 46.0,
					"life": ENT_LIFE, "cd": 0.0, "pw": pw,
				})
		"flood":
			for i in FLOOD_DIRS:
				var a := TAU * float(i) / float(FLOOD_DIRS)
				floods.append({
					"org": player.position, "dir": Vector2(cos(a), sin(a)),
					"d": 0.0, "hit": {}, "pw": pw,
				})
		"domain":
			domains.append({"pos": player.position, "left": DOMAIN_TIME, "pw": pw})
		"swords":
			_cast_swords(pw)
		"alpha":
			alpha_left = ALPHA_HITS
			alpha_gap = 0.0
			player.visible = false   # 施法瞬间就该消失，别等下一帧 _update_alpha 才隐身
			player.invuln = maxf(player.invuln, float(ALPHA_HITS) * ALPHA_GAP + 0.1)
	return false

## 雷霆万钧：随机挑几个倒霉蛋劈下去，每道雷连带炸伤它周围一小片。
func _cast_thunder(pw: float) -> void:
	var pool := enemies.filter(func(e): return not e.dead)
	pool.shuffle()
	for i in mini(THUNDER_BOLTS, pool.size()):
		var target: Enemy = pool[i]
		var pos: Vector2 = target.position
		bolts.append({"a": pos + Vector2(randf_range(-30.0, 30.0), -260.0), "b": pos, "t": 0.0})
		rings.append({"pos": pos, "r": THUNDER_RADIUS, "t": 0.0})
		clear_enemy_bullets_in(pos, THUNDER_RADIUS)
		for e in enemies.duplicate():
			if not e.dead and e.position.distance_to(pos) <= THUNDER_RADIUS + float(e.cfg.radius):
				_damage(e, THUNDER_DMG * pw, true, "normal")
	if not pool.is_empty():
		_shake(SHAKE_BURST, SHAKE_BURST_TIME)

## 无限剑阵：内外两圈剑位，外圈起手晚半拍，落下时各自砸一个圆。
func _cast_swords(pw: float) -> void:
	var base := player.position
	for ring in [[SWORD_INNER, SWORD_R_IN, 0.0], [SWORD_OUTER, SWORD_R_OUT, 0.18]]:
		var n := int(ring[0])
		for i in n:
			var a := TAU * float(i) / float(n) + randf() * 0.2
			swords.append({
				"pos": base + Vector2(cos(a), sin(a)) * float(ring[1]),
				"t": -float(ring[2]), "pw": pw,
			})

# ============================== DASH 冲刺 ==============================

func _begin_dash(path: PackedVector2Array, realtime := false) -> void:
	if path.size() < 2:
		state = State.PLAY
		return
	state = State.DASH
	dash_realtime = realtime
	dash_stamp += 1
	ink_path = path
	if ink_ages.size() != path.size():
		# 表盘斩 / 补斩这类非手绘轨迹没有真实计龄，整条按刚成形算
		ink_ages = WaterRenderer.synth_ages(path.size(), 0.0, 0.0)
	dash_pts = PackedVector2Array([player.position])
	for p in path:
		if p.distance_to(dash_pts[dash_pts.size() - 1]) > 0.01:
			dash_pts.append(p)
	dash_i = 0
	dash_d = 0.0
	dash_done = PackedVector2Array([path[0]])
	dash_ages = PackedFloat32Array([0.0])
	trail.clear()
	trail_acc = TRAIL_INTERVAL
	player.invuln = 999.0
	AudioMgr.play("dash", 1.0, -4.0)
	# §4 回溯记录：左键 / 右键每一次实际行进轨迹（含出发点）都入栈
	rewind_hist.append(dash_pts.duplicate())
	while rewind_hist.size() > rewind_slots():
		rewind_hist.remove_at(0)

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
		dash_ages.append(0.0)
	if dash_done.size() > 400:
		dash_done.remove_at(0)
		if dash_ages.size() > 0:
			dash_ages.remove_at(0)
	_spawn_trail(delta)
	if dash_i >= dash_pts.size() - 1:
		_begin_burst(false)

func _mark_enemies_at(pos: Vector2, dmg: float) -> void:
	clear_enemy_bullets_in(pos, dash_radius())
	for e in enemies:
		if e.position.distance_to(pos) <= dash_radius() + float(e.cfg.radius):
			if e.mark_stamp != dash_stamp:
				e.try_mark(sim_time, dash_stamp, dmg)
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
	if e == null or e.dead or e.invuln_left > 0.0:
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
	_split_on_death(e)
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

## 分裂怪死亡：按总表里该怪的 split_count / split_child_id 生成子体。
## 子体配置里 split_child_id 为空，所以不会二次分裂。
func _split_on_death(e: Enemy) -> void:
	if int(e.cfg.get("behavior", 0)) != EnemyData.Behavior.SPLITTER:
		return
	var child := String(e.cfg.get("split_child_id", ""))
	var n := int(e.cfg.get("split_count", 0))
	if child == "" or n <= 0 or not EnemyDB.has(child):
		return
	n = mini(n, maxi(max_enemies - enemies.size(), 0))
	if n <= 0:
		return
	var spread := float(e.cfg.get("split_spread", 46.0))
	var invuln := float(e.cfg.get("split_child_invuln", 0.5))
	var base := randf() * TAU
	var lo := Vector2(8, 8)
	var hi: Vector2 = ARENA - Vector2(8, 8)
	for i in n:
		var ang := base + TAU * float(i) / float(n)
		var dir := Vector2(cos(ang), sin(ang))
		var c := spawn_enemy_at(child, (e.position + dir * spread).clamp(lo, hi))
		if c != null:
			c.spawn_left = 0.18
			# 无敌一小会儿：父体的爆裂连锁就埋在脚下，不给这段子体必被秒
			c.invuln_left = invuln
			c.velocity = dir * float(c.cfg.speed)

# ============================== 敌方弹幕 ==============================
## 与技能命中一样走纯距离数学，不引入物理。子弹可被玩家的左键斩与右键神纹销毁。

func spawn_enemy_bullet(pos: Vector2, dir: Vector2, cfg: Dictionary) -> void:
	enemy_bullets.append({
		"pos": pos, "dir": dir,
		"spd": float(cfg.get("bullet_speed", 260.0)),
		"dmg": float(cfg.get("bullet_dmg", 6.0)),
		"r": float(cfg.get("bullet_radius", 10.0)),
		"life": float(cfg.get("bullet_life", 4.0)),
		"col": cfg.get("bullet_color", RED),
		"t": 0.0,
	})

func _update_enemy_bullets(delta: float, f: float) -> void:
	if enemy_bullets.is_empty():
		return
	var lo := Vector2(-48, -48)
	var hi: Vector2 = ARENA + Vector2(48, 48)
	for b in enemy_bullets:
		b.life = float(b.life) - delta * f
		b.t = float(b.t) + delta
		b.pos = b.pos + b.dir * float(b.spd) * delta * f
		if float(b.life) <= 0.0:
			continue
		if b.pos.x < lo.x or b.pos.y < lo.y or b.pos.x > hi.x or b.pos.y > hi.y:
			b.life = 0.0
			continue
		if player != null and f > 0.0 and state != State.GAMEOVER:
			if b.pos.distance_to(player.position) <= float(b.r) + Player.RADIUS:
				if player.take_hit(float(b.dmg)):
					b.life = 0.0
					_pop_bullet(b.pos, b.col)
					_on_player_hurt()
	enemy_bullets = enemy_bullets.filter(func(x): return float(x.life) > 0.0)

## 玩家吃到伤害后的统一反应：接触受击与中弹都走这里，别再各写一份。
func _on_player_hurt() -> void:
	hit_flash = 0.25
	AudioMgr.play("hit", 0.9, -2.0)
	clock_charge = maxf(clock_charge - HIT_CHARGE_PENALTY, 0.0)
	score_mult = maxf(score_mult - HIT_MULT_PENALTY, MULT_BASE)
	kill_streak = 0
	if player.hp <= 0.0:
		_enter_lag()

## 圆形清弹：技能范围内的敌弹一并销毁。返回销毁数量。
func clear_enemy_bullets_in(pos: Vector2, radius: float) -> int:
	if enemy_bullets.is_empty():
		return 0
	var n := 0
	for b in enemy_bullets:
		if float(b.life) > 0.0 and b.pos.distance_to(pos) <= radius + float(b.r):
			b.life = 0.0
			_pop_bullet(b.pos, b.col)
			n += 1
	if n > 0:
		enemy_bullets = enemy_bullets.filter(func(x): return float(x.life) > 0.0)
	return n

## 线段清弹：水漫金山那种向外推的浪，扫过的区间内敌弹一并销毁。
func clear_enemy_bullets_seg(org: Vector2, dir: Vector2, from_d: float, to_d: float, width: float) -> int:
	if enemy_bullets.is_empty():
		return 0
	var n := 0
	for b in enemy_bullets:
		if float(b.life) <= 0.0:
			continue
		var off: Vector2 = b.pos - org
		var along: float = off.dot(dir)
		if along < from_d or along > to_d:
			continue
		if absf(off.cross(dir)) > width + float(b.r):
			continue
		b.life = 0.0
		_pop_bullet(b.pos, b.col)
		n += 1
	if n > 0:
		enemy_bullets = enemy_bullets.filter(func(x): return float(x.life) > 0.0)
	return n

func _pop_bullet(pos: Vector2, col: Color) -> void:
	for i in 3:
		var ang := randf() * TAU
		particles.append({
			"pos": pos, "vel": Vector2(cos(ang), sin(ang)) * randf_range(50.0, 150.0),
			"life": 0.0, "max": randf_range(0.18, 0.32),
			"col": col, "r": randf_range(1.5, 3.5),
		})

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
	clear_enemy_bullets_in(pos, BOMB_RADIUS)
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

# ============================== 神纹驻场效果 ==============================

func _update_status(delta: float, f: float) -> void:
	for s in skills:
		if float(s.cd_left) > 0.0:
			s.cd_left = maxf(float(s.cd_left) - delta, 0.0)
	_update_blasts(delta)
	_update_enemy_bullets(delta, enemy_speed_factor())
	_update_quakes(delta)
	_update_ents(delta, f)
	_update_floods(delta)
	_update_domains(delta)
	_update_swords(delta)
	_update_alpha(delta)

## 山崩地裂：6 轮，每 0.5s 一轮，震源始终在玩家脚下。
func _update_quakes(delta: float) -> void:
	if quakes.is_empty():
		return
	for q in quakes:
		q.next -= delta
		if q.next > 0.0:
			continue
		q.next = QUAKE_GAP
		q.left = int(q.left) - 1
		var pos: Vector2 = player.position
		rings.append({"pos": pos, "r": QUAKE_RADIUS, "t": 0.0})
		_shake(SHAKE_DASH, SHAKE_DASH_TIME)
		clear_enemy_bullets_in(pos, QUAKE_RADIUS)
		for e in enemies.duplicate():
			if not e.dead and e.position.distance_to(pos) <= QUAKE_RADIUS + float(e.cfg.radius):
				_damage(e, QUAKE_DMG * float(q.pw), true, "normal")
	quakes = quakes.filter(func(x): return int(x.left) > 0)

## 妖木精灵：自由行动，各自扑最近的敌人，够近就砍一下。
func _update_ents(delta: float, f: float) -> void:
	if ents.is_empty():
		return
	for t in ents:
		t.life = float(t.life) - delta
		t.cd = maxf(float(t.cd) - delta, 0.0)
		var prey := _nearest_enemy(t.pos, 99999.0)
		if prey == null:
			continue
		var off: Vector2 = prey.position - t.pos
		var reach: float = ENT_REACH + float(prey.cfg.radius)
		if off.length() > reach:
			t.pos = t.pos + off.normalized() * ENT_SPEED * delta * maxf(f, 0.15)
		elif float(t.cd) <= 0.0:
			t.cd = ENT_GAP
			_damage(prey, ENT_DMG * float(t.pw), false, "normal")
	ents = ents.filter(func(x): return float(x.life) > 0.0)

## 水漫金山：八道浪从释放点向外推，每道浪对同一个目标只打一次。
func _update_floods(delta: float) -> void:
	if floods.is_empty():
		return
	for w in floods:
		var prev: float = float(w.d)
		w.d = prev + FLOOD_SPEED * delta
		clear_enemy_bullets_seg(w.org, w.dir, prev, float(w.d), FLOOD_WIDTH)
		for e in enemies.duplicate():
			if e.dead or w.hit.has(e.get_instance_id()):
				continue
			var off: Vector2 = e.position - w.org
			var along: float = off.dot(w.dir)
			if along < prev or along > float(w.d):
				continue
			if absf(off.cross(w.dir)) > FLOOD_WIDTH + float(e.cfg.radius):
				continue
			w.hit[e.get_instance_id()] = true
			_damage(e, FLOOD_DMG * float(w.pw), true, "normal")
	floods = floods.filter(func(x): return float(x.d) < FLOOD_RANGE)

## 时间领域：领域内持续掉血；玩家站在里面时钟表额外充能（回溯来得更快）。
func _update_domains(delta: float) -> void:
	if domains.is_empty():
		return
	for d in domains:
		d.left = float(d.left) - delta
		clear_enemy_bullets_in(d.pos, DOMAIN_RADIUS)
		for e in enemies.duplicate():
			if e.dead:
				continue
			if e.position.distance_to(d.pos) <= DOMAIN_RADIUS + float(e.cfg.radius):
				e.hp -= DOMAIN_DPS * float(d.pw) * delta
				if e.hp <= 0.0:
					_kill_enemy(e, "normal")
		if player.position.distance_to(d.pos) <= DOMAIN_RADIUS and clock_charge < CLOCK_TIME:
			clock_charge = minf(clock_charge + delta * (DOMAIN_CHARGE - 1.0), CLOCK_TIME)
	domains = domains.filter(func(x): return float(x.left) > 0.0)

## 无限剑阵：内圈先落外圈后落，剑尖着地砸一个圆。
func _update_swords(delta: float) -> void:
	if swords.is_empty():
		return
	for s in swords:
		var prev: float = float(s.t)
		s.t = prev + delta
		if prev >= SWORD_FALL or float(s.t) < SWORD_FALL:
			continue
		rings.append({"pos": s.pos, "r": SWORD_RADIUS, "t": 0.0})
		clear_enemy_bullets_in(s.pos, SWORD_RADIUS)
		for e in enemies.duplicate():
			if not e.dead and e.position.distance_to(s.pos) <= SWORD_RADIUS + float(e.cfg.radius):
				_damage(e, SWORD_DMG * float(s.pw), true, "normal")
	swords = swords.filter(func(x): return float(x.t) < SWORD_FALL + 0.2)

## 阿尔法突袭：玩家隐去无法被选中，每 ALPHA_GAP 秒对范围内随机一人补一刀。
func _update_alpha(delta: float) -> void:
	if alpha_left <= 0:
		if not player.visible:
			player.visible = true
		return
	player.visible = false
	player.invuln = maxf(player.invuln, 0.2)
	alpha_gap -= delta
	if alpha_gap > 0.0:
		return
	alpha_gap = ALPHA_GAP
	alpha_left -= 1
	var prey := _nearest_enemy(player.position + Vector2(
		randf_range(-ALPHA_RADIUS, ALPHA_RADIUS),
		randf_range(-ALPHA_RADIUS, ALPHA_RADIUS)), ALPHA_RADIUS)
	if prey == null:
		return
	ghost_trail.append({"pos": prey.position, "t": 0.0})
	_damage(prey, ALPHA_DMG * skill_power(), true, "normal")
	if alpha_left <= 0:
		player.visible = true
		_shake(SHAKE_BURST, SHAKE_BURST_TIME)

func _nearest_enemy(from: Vector2, limit: float) -> Enemy:
	var best: Enemy = null
	var best_d := limit
	for e in enemies:
		if e.dead:
			continue
		var d := e.position.distance_to(from)
		if d <= best_d:
			best_d = d
			best = e
	return best

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
	if path.is_empty():
		return player.position
	return SpellMatch.point_along(path, t)

# ============================== §8 受击 / 时滞 ==============================

func _check_contact() -> void:
	if player.invuln > 0.0:
		return
	for e in enemies:
		if e.dead or e.spawn_left > 0.0:
			continue
		if e.position.distance_to(player.position) <= float(e.cfg.radius) + Player.RADIUS:
			if player.take_hit(float(e.cfg.dmg)):
				var away := (e.position - player.position).normalized()
				e.position += away * 26.0
				_on_player_hurt()
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

## 当前时刻该用哪一段波表。跑过最后一段后一直用它（永久平台期），本局没有时限。
func _wave_seg() -> WaveData:
	return WaveDB.seg_for(run_time)

func _update_waves(delta: float, factor: float) -> void:
	var seg := _wave_seg()
	if seg == null:
		return
	spawn_timer -= delta * factor
	if spawn_timer <= 0.0:
		spawn_timer = seg.interval
		if enemies.size() < mini(seg.cap, max_enemies):
			spawn_enemy_at(seg.roll(randf()), _edge_pos())

## 按 id 在指定位置生成一只怪。刷怪表、分裂、测试都走这里。
func spawn_enemy_at(id: String, pos: Vector2) -> Enemy:
	var cfg := EnemyDB.cfg(id)
	if cfg.is_empty():
		return null
	var e := Enemy.new()
	e.position = pos
	e.setup(cfg, self, key_mat)
	add_child(e)
	enemies.append(e)
	return e

func _edge_pos() -> Vector2:
	var m := spawn_margin
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
	# 水痕计龄：与编辑器 _Pad._process 同构，逐点变老
	surface_phase += delta
	for i in ink_ages.size():
		ink_ages[i] += delta
	for i in dash_ages.size():
		dash_ages[i] += delta
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
	# 底：与 F1 编辑器试笔画布同一套水面（按编辑器画布尺寸平铺，底纹特征大小一致）
	var vs := get_viewport_rect().size
	var view := Rect2(camera.get_screen_center_position() - vs * 0.5, vs).grow(WaterRenderer.TILE.x)
	WaterRenderer.draw_water_surface_tiled(l, Rect2(Vector2.ZERO, ARENA), view, {}, surface_phase)

func _paint_ink(l: PaintLayer) -> void:
	# 水痕：飞鸟掠水的流体尾迹（参数来自 WaterRenderer.current，F1 编辑器保存即生效）。
	# 逐点年龄驱动淡出，与编辑器试笔画布同一套动态，故 alpha 恒为 1.0。
	if ink_path.size() >= 2 and ink_ages.size() == ink_path.size():
		WaterRenderer.draw_water_path(l, ink_path, ink_ages, 1.0)
	if state == State.DASH or state == State.BURST:
		if dash_done.size() >= 2 and dash_ages.size() == dash_done.size():
			WaterRenderer.draw_water_path(l, dash_done, dash_ages, 1.0)
	if state == State.REWIND:
		# 历史轨迹没有逐点计龄，按「起点最老、终点最新」铺一条等价年龄带
		var span := WaterRenderer.getf(WaterRenderer.current, "life_time") * 0.5
		for path in rewind_hist:
			if path.size() >= 2:
				WaterRenderer.draw_water_path(l, path,
					WaterRenderer.synth_ages(path.size(), 0.0, span), 1.0)

func _paint_fx(l: PaintLayer) -> void:
	for t in trail:
		var k: float = 1.0 - t.t / TRAIL_FADE
		_draw_silhouette(l, t.pos, k * 0.4, INK)
	for g in ghost_trail:
		var k2: float = 1.0 - g.t / TRAIL_FADE
		_draw_silhouette(l, g.pos, k2 * 0.55, RED)
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
	for b in enemy_bullets:
		var bc: Color = b.col
		var br: float = float(b.r)
		l.draw_line(b.pos - b.dir * br * 2.4, b.pos, Color(bc.r, bc.g, bc.b, 0.3), br * 0.8)
		l.draw_circle(b.pos, br, Color(bc.r, bc.g, bc.b, 0.9))
		l.draw_arc(b.pos, br + 2.0, 0.0, TAU, 12, Color(RED.r, RED.g, RED.b, 0.55), 1.5)
	_paint_spells(l)
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
	_paint_dial(l)

## 神纹驻场物：树人、水浪、时之领域、悬空待落的剑。
func _paint_spells(l: PaintLayer) -> void:
	for t in ents:
		var a: float = clampf(float(t.life) / 1.5, 0.0, 1.0)
		_draw_silhouette(l, t.pos, a * 0.55, GREY)
		l.draw_arc(t.pos, 16.0, 0.0, TAU, 16, Color(0.32, 0.44, 0.24, a * 0.8), 2.0)
	for w in floods:
		var wa: float = clampf(1.0 - float(w.d) / FLOOD_RANGE, 0.0, 1.0)
		var head: Vector2 = w.org + w.dir * float(w.d)
		var perp: Vector2 = Vector2(-w.dir.y, w.dir.x) * FLOOD_WIDTH
		l.draw_line(head - perp, head + perp, Color(0.28, 0.42, 0.55, wa * 0.85), 5.0)
		l.draw_line(head - perp * 0.5 - w.dir * 26.0, head + perp * 0.5 - w.dir * 26.0,
			Color(0.28, 0.42, 0.55, wa * 0.4), 3.0)
	for d in domains:
		var da: float = clampf(float(d.left) / DOMAIN_TIME, 0.0, 1.0)
		l.draw_circle(d.pos, DOMAIN_RADIUS, Color(RED.r, RED.g, RED.b, 0.05 * da))
		l.draw_arc(d.pos, DOMAIN_RADIUS, 0.0, TAU, 64,
			Color(RED.r, RED.g, RED.b, 0.3 + 0.25 * da), 2.5)
		l.draw_arc(d.pos, DOMAIN_RADIUS * (0.3 + 0.7 * fmod(sim_time, 1.0)), 0.0, TAU, 48,
			Color(RED.r, RED.g, RED.b, 0.18 * da), 1.5)
	for s in swords:
		var t2: float = float(s.t)
		if t2 >= SWORD_FALL:
			continue
		var k: float = clampf(t2 / SWORD_FALL, 0.0, 1.0)
		var tip: Vector2 = s.pos + Vector2(0.0, -300.0 * (1.0 - k))
		l.draw_line(tip + Vector2(0, -30), tip, Color(INK.r, INK.g, INK.b, 0.85), 3.0)
		l.draw_arc(s.pos, SWORD_RADIUS * k, 0.0, TAU, 24,
			Color(GREY.r, GREY.g, GREY.b, 0.25), 1.0)

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
	# 时针（唯一锚定斩击方向）：蓝色水晶指针素材，未就位时代码线兜底
	var ready := ap >= 1.0
	if dial_pointer != null:
		dial_pointer.global_position = c
		dial_pointer.rotation = hour_dir().angle()
		dial_pointer.modulate = Color(1, 1, 1, 1.0) if ready else Color(0.6, 0.6, 0.65, 0.4)
	else:
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
		var p := c + Vector2(-w * 0.5 + 12.0 * float(i), -70.0)
		if i < full:
			l.draw_circle(p, 4.0, Color(INK.r, INK.g, INK.b, 0.9))
		else:
			l.draw_arc(p, 4.0, 0.0, TAU, 12, Color(GREY.r, GREY.g, GREY.b, 0.5), 1.0)

func _draw_silhouette(l: PaintLayer, pos: Vector2, alpha: float, col: Color) -> void:
	var c := Color(col.r, col.g, col.b, alpha)
	l.draw_circle(pos, 9.0, c)
	var pts := PackedVector2Array([
		pos + Vector2(-11, 13), pos + Vector2(0, -14), pos + Vector2(11, 13),
	])
	l.draw_colored_polygon(pts, c)
