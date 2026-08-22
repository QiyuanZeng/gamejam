class_name Game
extends Node2D
## 《墨时》主控制器 —— PLAY / DRAW / DASH / BURST / REWIND 五态机 + 波次 + 特效。
## 不画不动，画即冲刺；冲刺过门不结算，到达终点顿帧集中引爆。

enum State { PLAY, DRAW, DASH, BURST, REWIND, GAMEOVER }

const ARENA := Vector2(1152.0, 648.0)
const INK_MAX_BASE := 100.0
const INK_REGEN_BASE := 26.0
const INK_COST_PER_PX := 0.075
const DASH_SPEED := 2400.0
const DASH_RADIUS := 70.0
const DASH_DMG := 20.0
const REWIND_MULT := 2.0
const POST_DASH_INVULN := 0.3
const SAMPLE_DIST := 6.0
const CLOCK_TIME := 25.0
const REWIND_SLOTS := 3
const REWIND_PATH_TIME := 0.15
const BURST_FREEZE := 0.16
const MARK_RETAIN := 1.5
const PLAYER_HP := 100.0
const TRAIL_INTERVAL := 0.03
const TRAIL_FADE := 0.4
const FLASH_TIME := 0.1
const DRAW_ENEMY_FACTOR := 0.08
const MAX_ENEMIES := 130

const INK := Color("#1A1714")
const RED := Color("#C0392B")
const GREY := Color("#4A443C")

const ENEMY_CFGS := {
	"blob": {"type": "blob", "hp": 10.0, "speed": 60.0, "dmg": 8.0, "radius": 15.0,
		"tex_target": 42.0, "color": Color("#1A1714"), "tex": "res://assets/enemy_blob.png"},
	"fast": {"type": "fast", "hp": 6.0, "speed": 130.0, "dmg": 6.0, "radius": 11.0,
		"tex_target": 38.0, "color": Color("#4A443C"), "tex": "res://assets/enemy_fast.png"},
	"tank": {"type": "tank", "hp": 40.0, "speed": 35.0, "dmg": 15.0, "radius": 27.0,
		"tex_target": 86.0, "color": Color("#1A1714"), "tex": "res://assets/enemy_tank.png"},
}

## 局外增量接口（P2）：局间购买，立刻生效。浓墨/快笔/重演。
var upgrades := {"ink_max": 0, "ink_regen": 0, "rewind_slots": 0}

var state: State = State.PLAY
var sim_time := 0.0
var run_time := 0.0
var ink := INK_MAX_BASE
var clock_charge := 0.0
var kills := 0
var wave_idx := 0
var wave_rest := 1.2
var wave_comp := {}
var spawn_left := 0
var spawn_interval := 0.5
var spawn_timer := 0.0

var ink_path := PackedVector2Array()
var dry_pen := false
var path_alpha := 0.0
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

# ============================== 输入 ==============================

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode in [KEY_F1, KEY_F10]:
		_toggle_editor()
		get_viewport().set_input_as_handled()  # 吞掉本次按键：防同事件派发给新编辑器秒关
		return
	if state == State.GAMEOVER:
		var key: bool = event is InputEventKey and event.pressed \
			and event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_R]
		var click: bool = event is InputEventMouseButton and event.pressed
		if key or click:
			get_tree().reload_current_scene()
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed and state == State.PLAY:
				_begin_draw()
			elif not event.pressed and state == State.DRAW:
				_end_draw()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed and state == State.DRAW:
			_cancel_draw()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_R:
		if state == State.PLAY and clock_charge >= CLOCK_TIME:
			_begin_rewind()

var _editor_pending := false

func _toggle_editor() -> void:
	if ink_editor != null or _editor_pending:
		return
	# 延迟到本帧输入派发结束后再实例化：否则新建的编辑器会在同一次派发里
	# 收到这个 F1 按下事件并把自己当关闭键 → 瞬开瞬关（set_input_as_handled
	# 只影响 _unhandled_input/_gui_input 阶段，拦不住 _input 全树分发）
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
	if state == State.DRAW:
		_cancel_draw()  # 编辑器打开期间松开左键，墨迹作废

func _clamped_mouse() -> Vector2:
	var m := get_global_mouse_position()
	return Vector2(
		clampf(m.x, 8.0, ARENA.x - 8.0),
		clampf(m.y, 8.0, ARENA.y - 8.0))

# ============================== 主循环 ==============================

func _process(delta: float) -> void:
	sim_time += delta
	if state != State.GAMEOVER:
		run_time += delta
	match state:
		State.PLAY:
			ink = minf(ink + ink_regen() * delta, ink_max())
			if clock_charge < CLOCK_TIME:
				clock_charge = minf(clock_charge + delta, CLOCK_TIME)
				if clock_charge >= CLOCK_TIME:
					AudioMgr.play("clock", 1.0, -4.0)
			_update_waves(delta, 1.0)
		State.DRAW:
			_sample_ink()
			_update_waves(delta, DRAW_ENEMY_FACTOR)
		State.DASH:
			_update_dash(delta)
		State.BURST:
			_update_burst(delta)
		State.REWIND:
			_update_rewind(delta)
		State.GAMEOVER:
			pass
	if state == State.PLAY or state == State.DRAW:
		_check_contact()
		_separate()
	if state != State.BURST:
		_update_fx(delta)
	_update_timers(delta)
	ink_layer.queue_redraw()
	fx_layer.queue_redraw()
	bg_layer.queue_redraw()
	hud.request_redraw()

func enemy_speed_factor() -> float:
	match state:
		State.PLAY:
			return 1.0
		State.DRAW:
			return DRAW_ENEMY_FACTOR
		_:
			return 0.0

func ink_max() -> float:
	return INK_MAX_BASE + 40.0 * float(upgrades.ink_max)

func ink_regen() -> float:
	return INK_REGEN_BASE + 12.0 * float(upgrades.ink_regen)

# ============================== DRAW 画墨 ==============================

func _begin_draw() -> void:
	if ink < 1.0:
		return
	state = State.DRAW
	dry_pen = false
	path_alpha = 1.0
	ink_path = PackedVector2Array()
	ink_path.append(_clamped_mouse())
	AudioMgr.play("draw", 1.2, -8.0)

func _sample_ink() -> void:
	if ink_path.is_empty() or dry_pen:
		return
	var m := _clamped_mouse()
	var last: Vector2 = ink_path[ink_path.size() - 1]
	var d := m.distance_to(last)
	if d < SAMPLE_DIST:
		return
	var cost := d * INK_COST_PER_PX
	if ink < cost:
		# 墨尽：只画到买得起的位置，笔尖干涸
		var afford := ink / INK_COST_PER_PX
		if afford >= 3.0:
			ink_path.append(last + (m - last).normalized() * afford)
		ink = 0.0
		dry_pen = true
		return
	ink_path.append(m)
	ink -= cost

func _cancel_draw() -> void:
	state = State.PLAY
	ink_path = PackedVector2Array()
	AudioMgr.play("cancel", 1.0, -8.0)

func _end_draw() -> void:
	if ink_path.size() >= 2:
		_begin_dash()
	else:
		state = State.PLAY

# ============================== DASH 冲刺 ==============================

func _begin_dash() -> void:
	state = State.DASH
	dash_stamp += 1
	# 先冲向墨迹起点，再沿墨迹掠过
	dash_pts = PackedVector2Array([player.position])
	for p in ink_path:
		dash_pts.append(p)
	dash_i = 0
	dash_d = 0.0
	# 视觉轨迹从墨迹起点开始（不含玩家接近段，避免起点发夹弯自交）
	dash_done = PackedVector2Array([ink_path[0]])
	trail.clear()
	trail_acc = TRAIL_INTERVAL
	player.invuln = 999.0
	AudioMgr.play("dash", 1.0, -4.0)
	# 记录回溯历史（最近 N 条墨迹）
	rewind_hist.append(ink_path.duplicate())
	var slots := REWIND_SLOTS + int(upgrades.rewind_slots)
	while rewind_hist.size() > slots:
		rewind_hist.remove_at(0)
	# 墨迹盖进渗墨画布（纸上留痕、缓慢晕开）
	bleed.stamp(ink_path, false)

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
	state = State.PLAY
	player.invuln = POST_DASH_INVULN
	path_alpha = 1.0
	if burst_rewind:
		ghost_trail.clear()

func _kill_enemy(e: Enemy) -> void:
	e.dead = true
	kills += 1
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
			if player.take_hit(float(e.cfg.dmg)):
				hit_flash = 0.25
				AudioMgr.play("hit", 0.9, -2.0)
				var away := (e.position - player.position).normalized()
				e.position += away * 26.0
			if player.hp <= 0.0:
				_game_over()
			return

func _game_over() -> void:
	state = State.GAMEOVER
	ink_path = PackedVector2Array()
	AudioMgr.play("over", 1.0, 0.0)

# ============================== 波次 ==============================

func _wave_config(w: int) -> Dictionary:
	if w <= 2:
		return {"count": 6 + 3 * (w - 1), "interval": 0.5, "blob": 1.0}
	elif w <= 4:
		return {"count": 6 + 3 * (w - 1), "interval": 0.45, "blob": 0.7, "fast": 0.3}
	return {"count": 8 + 3 * (w - 5), "interval": 0.4, "blob": 0.6, "fast": 0.25, "tank": 0.15}

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
	var m := 26.0
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
	if state == State.PLAY and path_alpha > 0.0:
		path_alpha = maxf(path_alpha - delta * 2.2, 0.0)

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
