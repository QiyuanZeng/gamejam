extends Node
## 咒语释放全链路模拟：右键起笔 → 按 6px 采样喂点（含 TV 扣费）→ 松笔 → 识别 → 释放。
## 覆盖：精确笔形 / 手写放大抖动 / 乱涂不误触 / 「时」接管状态 / 空位绑定后释放 / TV 门槛。

var g: Game
var phase := 0
var t := 0.0
var fails: Array[String] = []
var rng := RandomNumberGenerator.new()

var tank: Enemy
var pre_tv := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	rng.seed = 20260822
	g = Game.new()
	add_child(g)

func _process(delta: float) -> void:
	t += delta
	if g != null:
		g.spawn_timer = 9999.0
		g.player.invuln = 999.0
	match phase:
		0:
			if t > 0.5:
				tank = _place_at(Vector2(1060, 600), "tank")
				_reset()
				pre_tv = g.tv
				_write(_stroke(Game.fixed_stroke("zan"), 1.0, Vector2(300, 200), 0.0), 0.0)
				var s: Dictionary = g.skills[1]
				_chk(float(s.cd_left) > 0.0, "A 精确「斩」命中 cd=%.1f" % float(s.cd_left))
				_chk(tank != null and tank.hp <= 10.01,
					"A 全屏 30 伤命中远处坦克 hp=%.1f" % (tank.hp if tank != null else -1.0))
				_chk(g.state == g.State.DASH, "A 释放后仍照常斩击 state=%d" % g.state)
				print("     [笔长 %.0fpx  写完余 TV %.0f  扣费后 %.0f]" % [
					_len(g.ink_path), pre_tv - _len(g.ink_path), g.tv])
				_next(1)
		1:
			if _wait_play(2):
				pass
		2:
			# 手写：放大 1.8 倍 + 2px 抖动 + 1s 子弹时间流逝
			_reset()
			pre_tv = g.tv
			_write(_stroke(Game.fixed_stroke("zan"), 1.8, Vector2(240, 150), 2.0), 1.0)
			var s2: Dictionary = g.skills[1]
			var feat := g._stroke_feature(g.ink_path)
			_chk(float(s2.cd_left) > 0.0, "B 手写放大抖动版命中（余 TV %.0f）" % g.tv)
			_chk(not g.bind_panel, "B 命中咒语后不再弹绑定盘")
			print("     [笔长 %.0fpx  折点 %d  写完余 TV %.0f  门槛 120]" % [
				float(feat.get("px", 0.0)), int(feat.get("turns", -1)),
				pre_tv - float(feat.get("px", 0.0))])
			_next(3)
		3:
			if _wait_play(4):
				pass
		4:
			# 乱涂：小圆圈（笔长低于绑定阈值），不应命中任何咒语
			_reset()
			var circle := PackedVector2Array()
			for i in 33:
				var a := TAU * float(i) / 32.0
				circle.append(Vector2(400, 300) + Vector2(cos(a), sin(a)) * 38.0)
			_write(_densify(circle, 0.0), 0.0)
			_chk(not _any_cd(), "C 乱涂圆圈不误触咒语")
			_chk(not g.bind_panel, "C 乱涂未达绑定阈值")
			_chk(g.state == g.State.DASH, "C 乱涂仍出斩击 state=%d" % g.state)
			_next(5)
		5:
			if _wait_play(6):
				pass
		6:
			# 「时」：应接管状态直接进回溯，且不再斩击
			_chk(not g.rewind_hist.is_empty(), "D 已有回溯路径 %d 段" % g.rewind_hist.size())
			_place_at(g._point_along(g.rewind_hist[g.rewind_hist.size() - 1], 0.5), "blob")
			_reset()
			_write(_stroke(Game.fixed_stroke("time"), 1.4, Vector2(300, 220), 1.5), 0.0)
			var s3: Dictionary = g.skills[0]
			_chk(float(s3.cd_left) > 0.0, "D 「时」命中")
			_chk(g.state == g.State.REWIND, "D 「时」接管状态 → REWIND，state=%d" % g.state)
			_next(7)
		7:
			if _wait_play(8):
				pass
		8:
			# 绑定：长直线（≥ 上限 60%）→ 绑定盘 → 按 1 绑「雷链」
			_reset()
			var line := PackedVector2Array([Vector2(200, 500), Vector2(200 + 330, 500)])
			_write(_densify(line, 0.0), 0.0)
			_chk(g.bind_panel, "E 超长陌生笔形弹出绑定盘")
			g._input(_key(KEY_1))
			var s4: Dictionary = g.skills[2]
			_chk(bool(s4.bound), "E 按 1 绑定「%s」成功" % String(s4.name))
			_chk(not g.bind_panel, "E 绑定后关盘")
			_next(9)
		9:
			if _wait_play(10):
				pass
		10:
			# 复现同一笔形 → 雷链应释放
			for i in 3:
				_place_at(g.player.position + Vector2(-90.0 + 90.0 * i, -120.0), "blob")
			_reset()
			g.bolts.clear()
			var line2 := PackedVector2Array([Vector2(200, 500), Vector2(200 + 330, 500)])
			_write(_densify(line2, 0.0), 0.0)
			var s5: Dictionary = g.skills[2]
			_chk(float(s5.cd_left) > 0.0, "F 绑定后同笔形释放雷链")
			_chk(g.bolts.size() > 0, "F 雷链产生 %d 道电弧" % g.bolts.size())
			_next(11)
		11:
			if _wait_play(12):
				pass
		12:
			# TV 门槛：写完剩余 TV < 咒语耗费 → 不释放，只斩击
			_reset()
			g.tv = 250.0
			_write(_stroke(Game.fixed_stroke("zan"), 1.0, Vector2(300, 200), 0.0), 0.0)
			var s6: Dictionary = g.skills[1]
			_chk(float(s6.cd_left) <= 0.0, "G 写完余 TV %.0f < 120 → 不释放（只斩击）" % g.tv)
			_next(99)
		99:
			for f in fails:
				print("FAIL: ", f)
			print("SPELL ", "PASS" if fails.is_empty() else "FAIL")
			get_tree().quit(1 if not fails.is_empty() else 0)

# ============================== 驱动helper ==============================

func _next(p: int) -> void:
	phase = p
	t = 0.0

func _wait_play(p: int) -> bool:
	if g.state == g.State.PLAY:
		_next(p)
		return true
	if t > 6.0:
		_chk(false, "等待回到 PLAY 超时，state=%d" % g.state)
		_next(99)
	return false

func _reset() -> void:
	g.tv = g.tv_max()
	g.dry_pen = false
	for s in g.skills:
		s.cd_left = 0.0

func _any_cd() -> bool:
	for s in g.skills:
		if float(s.cd_left) > 0.0:
			return true
	return false

## 把控制点笔形缩放平移后按 6px 步长补点，可加抖动，模拟真人手写采样。
func _stroke(ctrl: PackedVector2Array, scale: float, origin: Vector2,
		jitter: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for p in ctrl:
		pts.append(p * scale + origin)
	return _densify(pts, jitter)

func _densify(ctrl: PackedVector2Array, jitter: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	if ctrl.is_empty():
		return out
	out.append(ctrl[0])
	for i in range(1, ctrl.size()):
		var a: Vector2 = ctrl[i - 1]
		var b: Vector2 = ctrl[i]
		var n: int = maxi(int(a.distance_to(b) / 6.0), 1)
		for k in range(1, n + 1):
			var p: Vector2 = a.lerp(b, float(k) / float(n))
			if jitter > 0.0:
				p += Vector2(rng.randf_range(-jitter, jitter), rng.randf_range(-jitter, jitter))
			out.append(p)
	return out

## 复刻 _sample_ink 的采样与扣费，再叠加 drain 秒的子弹时间流逝，最后松笔。
func _write(path: PackedVector2Array, drain: float) -> void:
	g._input(_btn(MOUSE_BUTTON_RIGHT, true))
	if g.state != g.State.SPELL:
		_chk(false, "起笔失败 state=%d tv=%.0f" % [g.state, g.tv])
		return
	g.ink_path = PackedVector2Array()
	g.dry_pen = false
	if path.is_empty():
		return
	g.ink_path.append(path[0])
	for i in range(1, path.size()):
		var last: Vector2 = g.ink_path[g.ink_path.size() - 1]
		var d: float = path[i].distance_to(last)
		if d < g.SAMPLE_DIST:
			continue
		var cost: float = d * g.TV_COST_PER_PX
		if g.tv < cost:
			g.tv = 0.0
			g.dry_pen = true
			break
		g.tv -= cost
		g.ink_path.append(path[i])
	g.tv = maxf(g.tv - g.BULLET_TV_DRAIN * drain, 0.0)
	g._input(_btn(MOUSE_BUTTON_RIGHT, false))

func _len(path: PackedVector2Array) -> float:
	var s := 0.0
	for i in path.size() - 1:
		s += path[i].distance_to(path[i + 1])
	return s

func _place_at(pos: Vector2, kind: String) -> Enemy:
	var e := Enemy.new()
	e.setup(g.ENEMY_CFGS[kind].duplicate(), g, null)
	e.position = pos
	e.spawn_left = 0.0
	g.add_child(e)
	g.enemies.append(e)
	return e

func _btn(idx: int, pressed: bool) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = idx as MouseButton
	ev.pressed = pressed
	return ev

func _key(k: Key, pressed := true) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = k
	ev.pressed = pressed
	return ev

func _chk(cond: bool, msg: String) -> void:
	print(("ok   " if cond else "BAD  "), msg)
	if not cond:
		fails.append(msg)
