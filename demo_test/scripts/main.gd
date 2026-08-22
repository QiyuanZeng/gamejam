class_name Game
extends Node2D
## 《墨时》主控制器 —— PLAY / DASH / BURST / REWIND / SPELL_DRAW 状态机 + 波次 + 特效。
## 左键时钟斩即唯一移动；回溯大招二次引爆斩击路径。

enum State { PLAY, DASH, BURST, REWIND, GAMEOVER, SPELL_DRAW }

const ARENA := Vector2(3000.0, 3000.0)
const VIEWPORT := Vector2(1152.0, 648.0)   # 渲染视口尺寸（bleed/相机参考）
const INK_MAX_BASE := 100.0
const INK_REGEN_BASE := 26.0
const DASH_SPEED := 2400.0
const DASH_RADIUS := 70.0
const DASH_DMG := 20.0
const REWIND_MULT := 1.0
const POST_DASH_INVULN := 0.3
const SAMPLE_DIST := 6.0
const CLOCK_TIME := 25.0
const REWIND_SLOTS := 5           # 回溯段数（策划案 5 段基础，BUG-04）
const REWIND_PATH_TIME := 0.15
const BURST_FREEZE := 0.16
const ROUND_TIME := 60.0         # 单局时长（BUG-06，30~60s，先用 60s）
const MARK_RETAIN := 1.5
const PLAYER_HP := 100.0
const TRAIL_INTERVAL := 0.03
const TRAIL_FADE := 0.4
const FLASH_TIME := 0.1
const MAX_ENEMIES := 130
const HIT_CHARGE_PENALTY := 8.0  # 受击扣回溯充能秒数（P0 BUG-01，无死亡机制）

## 时钟斩（v0.3 定案）：左键点击 = 普攻式冲刺，朝指针方向前冲固定距离
## 指针自转每满一圈 +1 行动点；行动点耗尽则左键无响应
const CLOCK_SWEEP_DEG := 180.0   # 2s/圈（360/180=2），决策节奏快
const CLOCK_DASH_DIST := 500.0   # 单次冲刺距离（策划案 500，BUG-03）
const AP_MAX := 3                # 行动点上限
const AP_START := 3              # 开局行动点

## 相机死区跟随：玩家在死区内相机不动，超出才跟随；超出安全距离强制 snap
const CAM_DEADZONE := 150.0      # 死区半径（玩家在此范围内相机不动）
const CAM_SAFE := 400.0          # 安全距离（超出强制 snap 防出框）
const CAM_LERP := 15.0           # 跟随速度系数

## —— 时间值（TV）：右键施法资源（老版 SPELL 系统移植） ——
const TIME_VALUE_MAX := 500.0    # BUG-08 对齐方案（原100，方案500）
const TIME_VALUE_REGEN := 20.0   # BUG-08 对齐方案（原5/s，方案20/s）
const TIME_VALUE_PER_KILL := 25.0 # BUG-08 对齐方案（原2/杀，方案25/杀）
const TV_MIN_CAST := 10.0
const SPELL_TIMESCALE := 0.3    # task-8：右键施法绘制时全局子弹时间（HUD 用 real_time 补偿）
## —— 连斩里程碑（老版移植）：回墨 / 五连回春 / 十连清场 / 十五连轮回 ——
const COMBO_3_INK := 10.0
const COMBO_5_HEAL := 30.0
const COMBO_10_DMG := 40.0
const COMBO_15_SCORE := 800
const COMBO_BREAK := 3.0
## —— 得分倍率（BUG-10）：连杀增长、受击衰减，无死亡机制的"软惩罚" ——
const SCORE_BASE := 10            # 基础击杀分
const SCORE_MULT_STEP := 0.1      # 每杀 +0.1 倍率
const SCORE_MULT_MAX := 3.0       # 20 连杀封顶
const SCORE_MULT_HIT_DECAY := 0.5 # 受击倍率减半（下限 1.0）

const INK := Color("#1A1714")
const RED := Color("#C0392B")
const GREY := Color("#4A443C")

const ENEMY_CFGS := {
	"blob": {"type": "blob", "hp": 30.0, "speed": 110.0, "dmg": 8.0, "radius": 15.0,
		"tex_target": 42.0, "color": Color("#1A1714"), "tex": "res://assets/enemy_blob.png"},
	"fast": {"type": "fast", "hp": 18.0, "speed": 200.0, "dmg": 6.0, "radius": 11.0,
		"tex_target": 38.0, "color": Color("#4A443C"), "tex": "res://assets/enemy_fast.png"},
	"tank": {"type": "tank", "hp": 90.0, "speed": 65.0, "dmg": 15.0, "radius": 27.0,
		"tex_target": 86.0, "color": Color("#1A1714"), "tex": "res://assets/enemy_tank.png"},
}

## 局外增量接口（P2）：局间购买，立刻生效。浓墨/快笔/重演。
var upgrades := {"ink_max": 0, "ink_regen": 0, "rewind_slots": 0}

var state: State = State.PLAY
var sim_time := 0.0
var real_time := 0.0   # 真实时间（time_scale 补偿），HUD 闪烁动画专用
var run_time := 0.0
var round_timer := ROUND_TIME    # BUG-06 单局倒计时
var swing_deg := -90.0   # 表盘指针角度：-90 = 12点方向为起点
var action_points := AP_START   # 当前行动点
var swing_accum := 0.0   # 指针自转累计度数，满 360 回复 1 点行动点
var ink := INK_MAX_BASE
var clock_charge := 0.0
var kills := 0
var wave_idx := 0
var wave_rest := 1.2
var wave_comp := {}
var spawn_left := 0
var spawn_interval := 0.5
var spawn_timer := 0.0

## —— SPELL / TV / 评分（老版移植） ——
var time_value := 40.0
var spell_points: Array[Vector2] = []
var spell_recognizer := SpellRecognizer.new()
var spell_caster: SpellCaster
var score := 0
var score_mult := 1.0   # 得分倍率（BUG-10）：连杀增长 / 受击减半
var combo := 0
var combo_timer := 0.0
var max_combo := 0

var dash_pts := PackedVector2Array()
var dash_i := 0
var dash_d := 0.0
var dash_done := PackedVector2Array()  # 冲刺已掠过轨迹（高亮灼芯绘制用）
var dash_stamp := 0
var burst_timer := 0.0
var burst_rewind := false
var combo_kills := 0

var rewind_hist: Array[PackedVector2Array] = []
var rewind_i := 0
var rewind_d := 0.0

var flash_t := 0.0
var hit_flash := 0.0
var announce_t := 0.0
var announce_text := ""
var zan_t := 0.0
var zan_text := "斬"
var zan_red := false
var help_t := 16.0

var trail: Array = []
var ghost_trail: Array = []
var particles: Array = []
var numbers: Array = []
var trail_acc := 0.0

var player: Player
var camera: Camera2D
var enemies: Array[Enemy] = []
var bleed: BleedCanvas
var bg_layer: PaintLayer
var ink_layer: PaintLayer
var fx_layer: PaintLayer
var clock_layer: PaintLayer
var hud: HUD
var key_mat: ShaderMaterial
var paper_tex: Texture2D

func _ready() -> void:
	randomize()
	# 防御：重开局时 time_scale 残留（Engine.time_scale 不随场景重载重置）
	Engine.time_scale = 1.0
	AudioServer.playback_speed_scale = 1.0
	var shader: Shader = load("res://shaders/paper_key.gdshader")
	if shader != null:
		key_mat = ShaderMaterial.new()
		key_mat.shader = shader
	if ResourceLoader.exists("res://assets/bg_paper.png"):
		paper_tex = load("res://assets/bg_paper.png")
	bg_layer = _make_layer(-100)
	ink_layer = _make_layer(-50)
	fx_layer = _make_layer(50)
	bg_layer.paint = _paint_bg
	ink_layer.paint = _paint_ink
	fx_layer.paint = _paint_fx
	clock_layer = _make_layer(-70)
	clock_layer.paint = _paint_clock
	bleed = BleedCanvas.new()
	bleed.z_index = -80
	add_child(bleed)
	player = Player.new()
	player.setup(key_mat)
	player.max_hp = PLAYER_HP
	player.hp = PLAYER_HP
	player.position = ARENA * 0.5
	add_child(player)
	camera = Camera2D.new()
	camera.position = player.position
	add_child(camera)
	camera.make_current()
	hud = HUD.new()
	hud.game = self
	add_child(hud)
	spell_caster = SpellCaster.new(self)

func _make_layer(z: int) -> PaintLayer:
	var l := PaintLayer.new()
	l.z_index = z
	add_child(l)
	return l

# ============================== 输入 ==============================

func _input(event: InputEvent) -> void:
	if state == State.GAMEOVER:
		var key: bool = event is InputEventKey and event.pressed \
			and event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_R]
		var click: bool = event is InputEventMouseButton and event.pressed
		if key or click:
			get_tree().reload_current_scene()
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed and state == State.PLAY and action_points > 0:
				_begin_swing_dash()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				if state == State.PLAY:
					if time_value < TV_MIN_CAST:
						numbers.append({
							"pos": player.position + Vector2(0, -20.0),
							"val": 0, "red": false, "t": 0.0,
						})
					else:
						_begin_spell()
			elif not event.pressed and state == State.SPELL_DRAW:
				_release_spell()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_R:
		if state == State.PLAY and clock_charge >= CLOCK_TIME:
			_begin_rewind()

func _clamped_mouse() -> Vector2:
	return get_global_mouse_position()

# ============================== 主循环 ==============================

func _process(delta: float) -> void:
	sim_time += delta
	real_time += delta / maxf(Engine.time_scale, 0.05)
	if state != State.GAMEOVER:
		run_time += delta
	if combo_timer > 0.0 and state != State.GAMEOVER:
		combo_timer -= delta
		if combo_timer <= 0.0:
			combo = 0
	match state:
		State.PLAY:
			var new_deg := swing_deg + CLOCK_SWEEP_DEG * delta
			swing_accum += CLOCK_SWEEP_DEG * delta
			# 指针自转满一圈 +1 行动点
			while swing_accum >= 360.0:
				swing_accum -= 360.0
				action_points = mini(action_points + 1, AP_MAX)
			swing_deg = fmod(new_deg, 360.0)
			ink = minf(ink + ink_regen() * delta, ink_max())
			time_value = minf(TIME_VALUE_MAX, time_value + TIME_VALUE_REGEN * delta)
			if clock_charge < CLOCK_TIME:
				clock_charge = minf(clock_charge + delta, CLOCK_TIME)
				if clock_charge >= CLOCK_TIME:
					AudioMgr.play("clock", 1.0, -4.0)
			_update_waves(delta, 1.0)
		State.SPELL_DRAW:
			_update_spell(delta)
		State.DASH:
			_update_dash(delta)
		State.BURST:
			_update_burst(delta)
		State.REWIND:
			_update_rewind(delta)
		State.GAMEOVER:
			pass
	if state == State.PLAY or state == State.SPELL_DRAW:
		_check_contact()
		_separate()
	if state != State.BURST:
		_update_fx(delta)
	# BUG-06 时限倒计时：非 GAMEOVER 态持续消耗
	if state != State.GAMEOVER:
		round_timer -= delta
		if round_timer <= 0.0:
			round_timer = 0.0
			_game_over()
	_update_timers(delta)
	ink_layer.queue_redraw()
	fx_layer.queue_redraw()
	bg_layer.queue_redraw()
	clock_layer.queue_redraw()
	hud.request_redraw()
	if camera != null and player != null:
		# 死区跟随：玩家在死区内相机不动（有位移感），超出才跟随；超安全距离强制 snap
		var offset := player.position - camera.position
		var dist := offset.length()
		if dist > CAM_SAFE:
			# 强制 snap：相机贴到距玩家 CAM_SAFE 处，防出框
			camera.position = player.position - offset.normalized() * CAM_SAFE
		elif dist > CAM_DEADZONE:
			# 死区外：lerp 跟随
			camera.position = camera.position.lerp(player.position, minf(1.0, delta * CAM_LERP))

func enemy_speed_factor() -> float:
	match state:
		State.PLAY:
			return 1.0
		State.DASH:
			return 1.0      # 移动即攻击，怪不停 = 割草压力
		State.SPELL_DRAW:
			return 1.0      # task-8：全局 time_scale=0.3 已减速，因子归一防双重减速
		State.BURST:
			return 0.2     # 顿帧微冻，引爆瞬间戏剧性
		State.REWIND:
			return 0.4     # 回溯慢镜但不完全冻
		_:
			return 0.0     # GAMEOVER

func ink_max() -> float:
	return INK_MAX_BASE + 40.0 * float(upgrades.ink_max)

func ink_regen() -> float:
	return INK_REGEN_BASE + 12.0 * float(upgrades.ink_regen)

# ============================== SPELL 施法（老版移植） ==============================

func _begin_spell() -> void:
	state = State.SPELL_DRAW
	spell_points.clear()
	spell_points.append(_clamped_mouse())
	# task-8 子弹时间：全局减速（怪/波次/特效/音效），鼠标采样不受影响
	Engine.time_scale = SPELL_TIMESCALE
	AudioServer.playback_speed_scale = SPELL_TIMESCALE
	AudioMgr.play("draw", 1.2, -8.0)

func _update_spell(delta: float) -> void:
	_add_spell_point(_clamped_mouse())
	_update_waves(delta, 1.0)  # time_scale 已全局减速，波次因子归一
	ink_layer.queue_redraw()
	fx_layer.queue_redraw()

func _add_spell_point(p: Vector2) -> void:
	if spell_points.is_empty():
		spell_points.append(p)
		return
	var last: Vector2 = spell_points[spell_points.size() - 1]
	if p.distance_to(last) < SAMPLE_DIST:
		return
	spell_points.append(p)

func _release_spell() -> void:
	_exit_bullet_time()
	var result := spell_recognizer.recognize(spell_points)
	if result.is_empty():
		state = State.PLAY
		numbers.append({
			"pos": player.position + Vector2(0, -30.0),
			"val": 0, "red": false, "t": 0.0,
		})
		return
	var cost: float = SpellRecognizer.SPELLS[result["id"]]["time_cost"]
	time_value = maxf(0.0, time_value - cost)
	spell_caster.cast(result["id"])
	state = State.PLAY

func start_rewind_from_spell() -> void:
	_begin_rewind()

func _exit_bullet_time() -> void:
	Engine.time_scale = 1.0
	AudioServer.playback_speed_scale = 1.0

func kill_list(died: Array) -> void:
	for e in died:
		if not e.dead:
			_kill_enemy(e)

# ============================== DASH 冲刺 ==============================

## 时钟斩：左键点击 → 朝表盘指针方向直线冲刺，击杀/等待 → 给右键咒语充能
func _begin_swing_dash() -> void:
	state = State.DASH
	dash_stamp += 1
	action_points = maxi(action_points - 1, 0)
	var dir := Vector2.from_angle(deg_to_rad(swing_deg))
	var end := player.position + dir * CLOCK_DASH_DIST
	dash_pts = PackedVector2Array([player.position, end])
	dash_i = 0
	dash_d = 0.0
	dash_done = PackedVector2Array([player.position])
	trail.clear()
	trail_acc = TRAIL_INTERVAL
	player.invuln = 999.0
	player.facing = dir
	AudioMgr.play("dash", 1.0, -4.0)
	rewind_hist.append(dash_pts.duplicate())
	var slots := REWIND_SLOTS + int(upgrades.rewind_slots)
	while rewind_hist.size() > slots:
		rewind_hist.remove_at(0)
	bleed.stamp(dash_pts, false)

## 时钟表盘：脚下圆环 + 时针 + 预测轨迹（指针指哪→冲刺去哪）+ 落点朱砂
func _paint_clock(l: PaintLayer) -> void:
	if player == null:
		return
	var c := player.position
	var dir := Vector2.from_angle(deg_to_rad(swing_deg))
	var r := 36.0
	# 预测轨迹（脚下→落点的淡色虚线，玩家一眼看出即将往哪走）
	var end := c + dir * CLOCK_DASH_DIST
	var seg := 14.0
	var gap := 8.0
	var total := CLOCK_DASH_DIST
	var t := 0.0
	while t < total:
		var a := c + dir * t
		var b := c + dir * minf(t + seg, total)
		l.draw_line(a, b, Color(0.75, 0.22, 0.17, 0.35), 3.0)
		t += seg + gap
	# 落点朱砂十字（预判命中位置）
	l.draw_line(end + Vector2(-6, 0), end + Vector2(6, 0), Color("#C0392B"), 2.0)
	l.draw_line(end + Vector2(0, -6), end + Vector2(0, 6), Color("#C0392B"), 2.0)
	# 底盘
	l.draw_circle(c, r, Color(0.0, 0.0, 0.0, 0.12))
	l.draw_arc(c, r, 0.0, TAU, 48, Color("#1A1714"), 2.5)
	# 12 点刻度（顺时针起点，加粗提示"总是从这里开始"）
	l.draw_line(c + Vector2(0, -r), c + Vector2(0, -r + 6), Color("#1A1714"), 3.0)
	# 3/6/9 点次要刻度
	l.draw_line(c + Vector2(r, 0), c + Vector2(r - 4, 0), Color("#4A443C"), 1.5)
	l.draw_line(c + Vector2(0, r), c + Vector2(0, r - 4), Color("#4A443C"), 1.5)
	l.draw_line(c + Vector2(-r, 0), c + Vector2(-r + 4, 0), Color("#4A443C"), 1.5)
	# 时针（粗黑，朱砂针尖 = 斩击方向）；行动点耗尽时针体变灰提示
	var hand_col := Color("#4A443C") if action_points <= 0 else Color("#1A1714")
	var tip_col := Color("#4A443C") if action_points <= 0 else Color("#C0392B")
	l.draw_line(c, c + dir * (r - 4.0), hand_col, 5.0)
	l.draw_circle(c + dir * (r - 4.0), 4.0, tip_col)
	# 顺时针方向提示箭头（外圈小弧）
	var next_ang := deg_to_rad(swing_deg + 24.0)
	var next_dir := Vector2.from_angle(next_ang)
	l.draw_line(c + dir * (r + 3), c + next_dir * (r + 3), Color("#4A443C"), 1.5)
	# 行动点圆点（表盘上方外圈弧形分布，已用=朱砂实心、可用=灰描边）
	for i in AP_MAX:
		# 3 点均布在 -150°~-30° 上弧（12 点上方），避免与时针/预测轨迹重叠
		var ang := deg_to_rad(-150.0 + 120.0 * float(i) / float(AP_MAX - 1 if AP_MAX > 1 else 1))
		var p := c + Vector2.from_angle(ang) * (r + 7.0)
		if i < action_points:
			l.draw_circle(p, 3.0, Color("#C0392B"))
		else:
			l.draw_arc(p, 3.0, 0.0, TAU, 16, Color("#4A443C"), 1.5)

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
		if e.position.distance_to(pos) <= DASH_RADIUS + float(e.cfg.radius):
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
	for e in enemies.duplicate():
		if e.dead or not e.is_marked(sim_time):
			continue
		var dmg: float = e.apply_mark()
		e.hp -= dmg
		numbers.append({
			"pos": e.position + Vector2(0, -float(e.cfg.radius)),
			"val": int(dmg), "red": burst_rewind, "t": 0.0,
		})
		if e.hp <= 0.0:
			killed.append(e)
	for e in killed:
		_kill_enemy(e)
	combo_kills = killed.size()
	var i := 0
	for e in killed:
		AudioMgr.play_later("kill", i * 0.05, 1.0 + 0.08 * i, -4.0)
		i += 1
	if not killed.is_empty():
		AudioMgr.play("burst", 0.85 if burst_rewind else 1.0, -3.0)
	if combo_kills >= 4:
		flash_t = FLASH_TIME
		zan_t = 0.5
		zan_red = burst_rewind
		zan_text = "斬"
	# 一斩 ≥3 杀：回墨（老版移植，策略：憋大招）
	if combo_kills >= 3:
		var bonus := COMBO_3_INK + 3.0 * float(combo_kills - 3)
		ink = minf(ink_max(), ink + minf(bonus, 25.0))
	_apply_combo_rewards()
	state = State.PLAY
	player.invuln = POST_DASH_INVULN
	if burst_rewind:
		ghost_trail.clear()

func _kill_enemy(e: Enemy) -> void:
	e.dead = true
	kills += 1
	score_mult = minf(SCORE_MULT_MAX, score_mult + SCORE_MULT_STEP)
	score += int(roundf(SCORE_BASE * score_mult))
	time_value = minf(TIME_VALUE_MAX, time_value + TIME_VALUE_PER_KILL)
	combo += 1
	max_combo = maxi(max_combo, combo)
	combo_timer = COMBO_BREAK
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
	e.queue_free()

## —— 连斩里程碑（老版移植）：一斩≥3回墨 / 五连回春 / 十连清场 / 十五连轮回 ——
func _apply_combo_rewards() -> void:
	if combo >= 15:
		score += COMBO_15_SCORE
		zan_t = 0.5
		zan_red = false
		zan_text = "十五连轮回"
		AudioMgr.play("burst", 1.0, -3.0)
	elif combo >= 10:
		var died: Array = []
		for e in enemies.duplicate():
			if e.dead:
				continue
			e.hp -= COMBO_10_DMG
			if e.hp <= 0.0:
				died.append(e)
		kill_list(died)
		zan_t = 0.5
		zan_red = false
		zan_text = "十连清场"
	elif combo >= 5:
		player.hp = minf(player.max_hp, player.hp + COMBO_5_HEAL)
		zan_t = 0.5
		zan_red = false
		zan_text = "五连回春"

# ============================== REWIND 回溯 ==============================

func _begin_rewind() -> void:
	if rewind_hist.is_empty():
		return
	state = State.REWIND
	clock_charge = 0.0
	rewind_i = 0
	rewind_d = 0.0
	ghost_trail.clear()
	player.invuln = 999.0
	zan_t = 0.5
	zan_red = true
	zan_text = "回溯"
	AudioMgr.play("rewind", 1.0, -2.0)

func _update_rewind(delta: float) -> void:
	if rewind_i >= rewind_hist.size():
		_begin_burst(true)
		return
	if rewind_d == 0.0:
		dash_stamp += 1
		bleed.stamp(rewind_hist[rewind_i], true)
	var path: PackedVector2Array = rewind_hist[rewind_i]
	rewind_d += delta / REWIND_PATH_TIME
	var pos := _point_along(path, clampf(rewind_d, 0.0, 1.0))
	_mark_enemies_at(pos, DASH_DMG * REWIND_MULT)
	ghost_trail.append({"pos": pos, "t": 0.0})
	if ghost_trail.size() > 240:
		ghost_trail.pop_front()
	if rewind_d >= 1.0:
		rewind_i += 1
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
		if acc + seg >= target:
			return path[i].lerp(path[i + 1], (target - acc) / seg)
		acc += seg
	return path[path.size() - 1]

# ============================== 接触伤害 ==============================

func _check_contact() -> void:
	if player.invuln > 0.0:
		return
	for e in enemies:
		if e.dead or e.spawn_left > 0.0:
			continue
		if e.position.distance_to(player.position) <= float(e.cfg.radius) + Player.RADIUS:
			# P0 BUG-01：玩家不死亡，受击扣回溯充能 + 清 combo
			# BUG-10：得分倍率减半（下限 1.0）
			hit_flash = 0.25
			AudioMgr.play("hit", 0.9, -2.0)
			player.invuln = Player.INVULN_TIME
			clock_charge = maxf(0.0, clock_charge - HIT_CHARGE_PENALTY)
			score_mult = maxf(1.0, score_mult * SCORE_MULT_HIT_DECAY)
			combo = 0
			combo_timer = 0.0
			var away := (e.position - player.position).normalized()
			e.position += away * 26.0
			return

func _game_over() -> void:
	_exit_bullet_time()  # 时限耗尽可能发生在 SPELL_DRAW 中，恢复时间流速
	state = State.GAMEOVER
	AudioMgr.play("over", 1.0, 0.0)

# ============================== 波次 ==============================

func _wave_config(w: int) -> Dictionary:
	if w <= 2:
		return {"count": 12 + 4 * (w - 1), "interval": 0.25, "blob": 1.0}
	elif w <= 4:
		return {"count": 12 + 4 * (w - 1), "interval": 0.22, "blob": 0.7, "fast": 0.3}
	return {"count": 16 + 4 * (w - 5), "interval": 0.2, "blob": 0.6, "fast": 0.25, "tank": 0.15}

func _update_waves(delta: float, factor: float) -> void:
	if spawn_left > 0:
		spawn_timer -= delta * factor
		if spawn_timer <= 0.0:
			spawn_timer += spawn_interval
			spawn_left -= 1
			_spawn_enemy()
	elif enemies.is_empty():
		wave_rest -= delta * factor
		if wave_rest <= 0.0:
			_next_wave()

func _next_wave() -> void:
	wave_idx += 1
	wave_comp = _wave_config(wave_idx)
	spawn_left = int(wave_comp.count)
	spawn_interval = float(wave_comp.interval)
	spawn_timer = 0.2
	wave_rest = 2.0
	announce_text = "第 %d 波" % wave_idx
	announce_t = 1.6
	AudioMgr.play("wave", 1.0, -6.0)

func _spawn_enemy() -> void:
	if enemies.size() >= MAX_ENEMIES:
		return
	var roll := randf()
	var acc := 0.0
	var type := "blob"
	for k in ["blob", "fast", "tank"]:
		if wave_comp.has(k):
			acc += float(wave_comp[k])
			if roll <= acc:
				type = k
				break
	var e := Enemy.new()
	e.position = _edge_pos()
	e.setup(ENEMY_CFGS[type].duplicate(), self, key_mat)
	add_child(e)
	enemies.append(e)

func _edge_pos() -> Vector2:
	# 玩家周围环形刷怪：半径 500-700px，随机角度（无固定边缘方向）
	var center := player.position if player != null else ARENA * 0.5
	var ang := randf() * TAU
	var r := randf_range(500.0, 700.0)
	return center + Vector2(cos(ang), sin(ang)) * r

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

# ============================== 绘制 ==============================

func _paint_bg(l: PaintLayer) -> void:
	# 纸纹平铺到世界坐标（tile=true），ARENA 3000×3000 全铺
	# 相机移动时纸纹相对屏幕滚动，有"在空间里穿行"的移动感
	if paper_tex != null:
		l.draw_texture_rect(paper_tex, Rect2(Vector2.ZERO, ARENA), true)
	else:
		l.draw_rect(Rect2(Vector2.ZERO, ARENA), Color("#F5F1E8"))
		# 円相：背景一枚巨大淡墨圆
		l.draw_arc(ARENA * 0.5, 235.0, 0.0, TAU, 96, Color(0.1, 0.09, 0.08, 0.06), 28.0)
		l.draw_arc(ARENA * 0.5, 235.0, 0.0, TAU, 96, Color(0.1, 0.09, 0.08, 0.04), 52.0)

func _paint_ink(l: PaintLayer) -> void:
	# 施法轨迹：朱砂
	if state == State.SPELL_DRAW and spell_points.size() >= 2:
		InkRenderer.draw_brush_path(l, spell_points, 0.9, true)
	# 冲刺掠过的轨迹
	if state == State.DASH or state == State.BURST:
		InkRenderer.draw_brush_path(l, dash_done, 0.95, false)
	# 回溯：旧轨迹朱红版
	if state == State.REWIND:
		for path in rewind_hist:
			if path.size() >= 2:
				InkRenderer.draw_brush_path(l, path, 0.6, true)

func _paint_fx(l: PaintLayer) -> void:
	# 冲刺残影（墨）
	for t in trail:
		var k: float = 1.0 - t.t / TRAIL_FADE
		_draw_silhouette(l, t.pos, k * 0.4, INK)
	# 回溯红色残影
	for g in ghost_trail:
		var k: float = 1.0 - g.t / TRAIL_FADE
		_draw_silhouette(l, g.pos, k * 0.55, RED)
	# 溅墨粒子
	for p in particles:
		var k: float = 1.0 - p.life / p.max
		var c: Color = p.col
		l.draw_circle(p.pos, float(p.r) * (0.5 + 0.5 * k),
			Color(c.r, c.g, c.b, clampf(k, 0.0, 1.0)))
	# 被标记怪：红痕 + 红环
	for e in enemies:
		if e.is_marked(sim_time):
			var r: float = float(e.cfg.radius) + 8.0
			var c := Color(RED.r, RED.g, RED.b, 0.9)
			var dir := Vector2(0.8, 0.6)
			l.draw_line(e.position + dir * r, e.position - dir * r, c, 3.0)
			var dir2 := Vector2(-0.6, 0.55)
			l.draw_line(e.position + dir2 * r * 0.9, e.position - dir2 * r * 0.9, c, 2.0)
			l.draw_arc(e.position, r + 5.0, 0.0, TAU, 24, Color(RED.r, RED.g, RED.b, 0.35), 1.5)

func _draw_silhouette(l: PaintLayer, pos: Vector2, alpha: float, col: Color) -> void:
	var c := Color(col.r, col.g, col.b, alpha)
	l.draw_circle(pos, 9.0, c)
	var pts := PackedVector2Array([
		pos + Vector2(-11, 13), pos + Vector2(0, -14), pos + Vector2(11, 13),
	])
	l.draw_colored_polygon(pts, c)
