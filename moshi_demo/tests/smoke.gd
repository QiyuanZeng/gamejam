extends Node
## 冒烟测试：PLAY→SPELL→DASH→BURST→PLAY→表盘斩→REWIND→时滞→结算。
## headless 直调 Game 内部 API + 伪造输入事件，确定性断言。

var g: Game
var phase := 0
var t := 0.0
var fails: Array[String] = []
var rewind_origin := Vector2.ZERO

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # 编辑器会暂停树，测试驱动必须继续跑
	g = Game.new()
	add_child(g)

func _process(delta: float) -> void:
	t += delta
	if g != null:
		g.spawn_timer = 9999.0  # 关掉自然生成，隔离测试环境
	match phase:
		0:
			if t > 0.5:
				_place(3)
				g._input(_btn(MOUSE_BUTTON_RIGHT, true))
				_chk(g.state == g.State.SPELL, "RMB press -> SPELL")
				g.ink_path = PackedVector2Array()
				g.ink_path.append(Vector2(400, 324))
				g.ink_path.append(Vector2(500, 324))
				g.ink_path.append(Vector2(650, 324))
				g._input(_btn(MOUSE_BUTTON_RIGHT, false))
				_chk(g.state == g.State.DASH, "RMB release -> DASH")
				_chk(not g.dash_realtime, "RMB dash freezes enemies")
				_chk(g.enemy_speed_factor() == 0.0, "RMB dash factor 0")
				phase = 1
				t = 0.0
		1:
			if g.state == g.State.PLAY:
				_chk(g.kills == 3, "burst kills 3, got %d" % g.kills)
				_chk(g.score > 0.0, "score accumulated, got %d" % int(g.score))
				phase = 2
				t = 0.0
			elif t > 5.0:
				_chk(false, "dash/burst timeout at state %d" % g.state)
				phase = 9
		2:
			# 左键表盘斩：时针归零 → 指向 12 点（-Y）
			g.dial_t = 0.0
			g.ap = 3.0
			g.last_slash = -99.0
			var target: Vector2 = g.player.position + Vector2(0, -140)
			_place_at(target)
				g._input(_btn(MOUSE_BUTTON_LEFT, true))
				_chk(g.state == g.State.DASH, "LMB -> dial dash")
				_chk(abs(g.ap - 2.0) < 0.01, "AP cost 1, got %.2f" % g.ap)
				_chk(g.dash_realtime, "LMB dash is realtime (no bullet time)")
				_chk(g.enemy_speed_factor() == 1.0, "LMB dash enemy factor 1.0, got %.2f"
					% g.enemy_speed_factor())
				_chk(g.player.invuln > 0.0, "LMB dash player invulnerable")
			phase = 3
			t = 0.0
		3:
			if g.state == g.State.PLAY:
				_chk(g.kills == 4, "dial slash kill, got %d" % g.kills)
				phase = 4
				t = 0.0
			elif t > 5.0:
				_chk(false, "dial dash timeout at state %d" % g.state)
				phase = 9
			4:
				var last: PackedVector2Array = g.rewind_hist[g.rewind_hist.size() - 1]
				_chk(g.rewind_hist.size() == 2, "hist records LMB+RMB, got %d"
					% g.rewind_hist.size())
				rewind_origin = g.rewind_hist[0][0]
				_place_at(g._point_along(last, 0.5))
				_place_at(g._point_along(last, 0.8))
				g.clock_charge = g.CLOCK_TIME
				g._input(_key(KEY_R))
				_chk(g.state == g.State.REWIND, "R -> REWIND")
				_chk(g.clock_charge == 0.0, "rewind clears charge")
				phase = 5
				t = 0.0
			5:
				if g.state == g.State.PLAY:
					_chk(g.kills == 6, "rewind kills 6, got %d" % g.kills)
					_chk(g.player.position.distance_to(rewind_origin) < 1.0,
						"player rewound to first path start %s, got %s"
						% [rewind_origin, g.player.position])
					phase = 6
					t = 0.0
				elif t > 5.0:
					_chk(false, "rewind timeout")
					phase = 9
		6:
			# F1 打开墨笔编辑器（编辑器延迟到帧末创建，防同事件秒关）
			g._input(_key(KEY_F1))
			phase = 7
			t = 0.0
		7:
			if g.ink_editor != null:
				_chk(true, "F1 opens editor")
				_chk(get_tree().paused, "tree paused while editor open")
				var ed: CanvasLayer = g.ink_editor
				ed._input(_key(KEY_F1, false))  # 松开开启键 → 武装
				ed._input(_key(KEY_F1))         # 再按 → 关闭
				phase = 8
				t = 0.0
			elif t > 1.0:
				_chk(false, "F1 opens editor")
				_chk(false, "tree paused while editor open")
				phase = 10
				t = 0.0
		8:
			if t > 0.1:
				_chk(g.ink_editor == null, "editor closed by F1")
				_chk(not get_tree().paused, "tree unpaused after close")
				phase = 10
				t = 0.0
		10:
			# 时滞：HP 归零不死亡
			g.player.invuln = 0.0
			g.player.hp = 5.0
			g.score_mult = 1.4
			_place(1, true)
			phase = 11
			t = 0.0
		11:
			if g.state == g.State.LAG:
				_chk(g.lag_count == 1, "hp<=0 -> LAG once, got %d" % g.lag_count)
				_chk(g.ap == 0.0, "LAG clears AP")
				_chk(g.score_mult < 1.4, "hit lowers score mult, got %.2f" % g.score_mult)
				phase = 12
				t = 0.0
			elif t > 5.0:
				_chk(false, "lag timeout, state %d hp %f" % [g.state, g.player.hp])
				phase = 9
		12:
			if g.state == g.State.PLAY:
				_chk(g.player.hp == g.player.max_hp, "LAG restores HP")
				phase = 13
				t = 0.0
			elif t > 6.0:
				_chk(false, "lag exit timeout, state %d" % g.state)
				phase = 9
		13:
			g.run_time = g.RUN_LIMIT
			phase = 14
			t = 0.0
		14:
			if g.state == g.State.GAMEOVER:
				_chk(g.rating != "", "settle rating %s" % g.rating)
				_chk(g.payout_coins > 0, "settle coins %d" % g.payout_coins)
				phase = 9
			elif t > 2.0:
				_chk(false, "settle timeout, state %d" % g.state)
				phase = 9
		9:
			for f in fails:
				print("FAIL: ", f)
			print("SMOKE ", "PASS" if fails.is_empty() else "FAIL")
			get_tree().quit(1 if not fails.is_empty() else 0)

func _place(n: int, on_player := false) -> void:
	for i in n:
		var pos: Vector2 = g.player.position + Vector2(2, 0) if on_player \
			else g.player.position + Vector2(-120.0 + 110.0 * i, 0)
		_place_at(pos)

func _place_at(pos: Vector2) -> void:
	var e := Enemy.new()
	e.setup(g.ENEMY_CFGS["blob"].duplicate(), g, null)
	e.position = pos
	e.spawn_left = 0.0
	g.add_child(e)
	g.enemies.append(e)

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
