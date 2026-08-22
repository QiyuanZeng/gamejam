extends Node
## 表盘倒转（空格）+ 边界反弹（左键斩撞墙折回）双特性测试。
## headless 直调 Game 内部 API，确定性断言，不依赖渲染。

var g: Game
var t := 0.0
var life := 0.0
var phase := 0
var fails: Array[String] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	g = Game.new()
	add_child(g)

func _process(delta: float) -> void:
	t += delta
	life += delta
	if life > 25.0:
		print("FAIL: watchdog at phase %d" % phase)
		print("DIAL_BOUNCE FAIL")
		get_tree().quit(1)
		return
	if g != null:
		g.spawn_timer = 9999.0
	match phase:
		0:
			if t > 0.5:
				_test_flip()
				_test_bounce_unit()
				phase = 1
				t = 0.0
		1:
			# 端到端：贴着右墙往 +X 斩，应该折回来而不是被削短
			g.state = g.State.PLAY
			g.player.position = Vector2(2900.0, 1500.0)
			g.dial_dir = 1.0
			g.dial_t = 0.25 * g.HOUR_PERIOD      # 3 点 → +X
			g.ap = 3.0
			g.last_slash = -99.0
			var d0 := g.hour_dir()
			_chk(d0.x > 0.99, "dial 3点指向 +X, got %s" % str(d0))
			g._dial_slash()
			_chk(g.state == g.State.DASH, "slash -> DASH, got %d" % g.state)
			var pts: PackedVector2Array = g.dash_pts
			var maxx := -1e9
			var total := 0.0
			var turned := false
			for i in pts.size():
				maxx = maxf(maxx, pts[i].x)
				if i > 0:
					total += pts[i - 1].distance_to(pts[i])
					if pts[i].x < pts[i - 1].x - 0.01:
						turned = true
			_chk(maxx <= 2992.01, "路径不越界, maxx=%.1f" % maxx)
			_chk(turned, "撞墙后 x 方向反转（发生反弹）")
			_chk(absf(total - g.dash_dist()) < 6.0,
				"冲刺全长保留 %.1f / 应为 %.1f" % [total, g.dash_dist()])
			phase = 2
			t = 0.0
		2:
			# 倒转后再斩：方向应跟着表盘反着来
			if g.state != g.State.PLAY and t < 6.0:
				return
			g.state = g.State.PLAY
			g.player.position = Vector2(1500.0, 1500.0)
			g.dial_t = 0.0
			g.dial_dir = 1.0
			g._input(_key(KEY_SPACE))
			_chk(g.dial_dir < 0.0, "空格 -> 表盘倒转, dir=%.1f" % g.dial_dir)
			g._regen(0.25, 1.0)                  # 倒着走四分之一圈 → 9 点
			var dr := g.hour_dir()
			_chk(dr.x < -0.99, "倒转四分之一圈指向 -X, got %s" % str(dr))
			g.ap = 3.0
			g.last_slash = -99.0
			g._dial_slash()
			var first: Vector2 = g.dash_pts[1] - g.dash_pts[0]
			_chk(first.normalized().x < -0.99,
				"斩击起手方向跟随倒转后的表盘, got %s" % str(first.normalized()))
			phase = 9
		9:
			for f in fails:
				print("FAIL: %s" % f)
			print("DIAL_BOUNCE ", "PASS" if fails.is_empty() else "FAIL")
			get_tree().quit(1 if not fails.is_empty() else 0)

func _test_flip() -> void:
	g.state = g.State.PLAY
	g.dial_dir = 1.0
	g.dial_t = 0.0
	g._regen(0.25, 1.0)
	_chk(absf(g.dial_t - 0.25) < 1e-4, "正走 dial_t=%.3f" % g.dial_t)
	var fwd := g.hour_dir()
	_chk(fwd.x > 0.99, "正走四分之一圈指向 +X, got %s" % str(fwd))
	g._input(_key(KEY_SPACE))
	_chk(g.dial_dir < 0.0, "空格切到倒转")
	g._regen(0.5, 1.0)
	_chk(absf(g.dial_t + 0.25) < 1e-4, "倒转后 dial_t 回退到 %.3f" % g.dial_t)
	g._input(_key(KEY_SPACE))
	_chk(g.dial_dir > 0.0, "再按空格切回正走")

func _test_bounce_unit() -> void:
	var lo := 8.0
	var hi := 2992.0
	# 1) 不碰墙：原样直达
	var p0: PackedVector2Array = g._bounce_path(Vector2(1500, 1500), Vector2(1, 0), 100.0)
	_chk(p0.size() == 2, "场中央不反弹, pts=%d" % p0.size())
	_chk(absf(p0[1].x - 1600.0) < 0.01, "直达终点 x=%.1f" % p0[1].x)
	# 2) 单边反弹：右墙
	var p1: PackedVector2Array = g._bounce_path(Vector2(2980, 1500), Vector2(1, 0), 100.0)
	_chk(p1.size() == 3, "右墙一次反弹, pts=%d" % p1.size())
	_chk(absf(p1[1].x - hi) < 0.01, "拐点落在墙上 x=%.1f" % p1[1].x)
	_chk(absf(p1[2].x - (hi - 88.0)) < 0.01, "折回终点 x=%.1f 应为 %.1f" % [p1[2].x, hi - 88.0])
	_chk(absf(_len(p1) - 100.0) < 0.01, "反弹后总长仍为 %.2f" % _len(p1))
	# 3) 角落双反弹
	var p2: PackedVector2Array = g._bounce_path(Vector2(2960, 2960), Vector2(1, 1).normalized(), 200.0)
	_chk(p2.size() >= 3, "角落至少一次反弹, pts=%d" % p2.size())
	_chk(absf(_len(p2) - 200.0) < 0.05, "角落反弹总长 %.2f" % _len(p2))
	_chk(_inside(p2, lo, hi), "角落反弹全程在场内")
	# 4) 极端：贴墙起手朝墙外
	var p3: PackedVector2Array = g._bounce_path(Vector2(hi, 1500), Vector2(1, 0), 150.0)
	_chk(_inside(p3, lo, hi), "贴墙起手不越界")
	_chk(absf(_len(p3) - 150.0) < 0.05, "贴墙起手总长 %.2f" % _len(p3))

func _len(p: PackedVector2Array) -> float:
	var s := 0.0
	for i in range(1, p.size()):
		s += p[i - 1].distance_to(p[i])
	return s

func _inside(p: PackedVector2Array, lo: float, hi: float) -> bool:
	for v in p:
		if v.x < lo - 0.01 or v.x > hi + 0.01 or v.y < lo - 0.01 or v.y > hi + 0.01:
			return false
	return true

func _key(code: Key) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	return ev

func _chk(cond: bool, msg: String) -> void:
	if cond:
		print("ok   %s" % msg)
	else:
		print("BAD  %s" % msg)
		fails.append(msg)
