extends Node
## 冒烟测试：状态机全链路 PLAY→DRAW→DASH→BURST→PLAY→REWIND→GAMEOVER。
## headless 直调 Game 内部 API + 伪造输入事件，确定性断言。

var g: Game
var phase := 0
var t := 0.0
var fails: Array[String] = []

func _ready() -> void:
	g = Game.new()
	add_child(g)
	g.wave_rest = 999.0  # 推迟自然波次，隔离测试环境

func _process(delta: float) -> void:
	t += delta
	match phase:
		0:
			if t > 0.5:
				_place(3)
				g._input(_btn(MOUSE_BUTTON_LEFT, true))
				_chk(g.state == g.State.DRAW, "LMB press -> DRAW")
				g.ink_path.append(Vector2(400, 324))
				g.ink_path.append(Vector2(500, 324))
				g.ink_path.append(Vector2(650, 324))
				_chk(g.ink_path.size() >= 2, "ink path recorded")
				g._input(_btn(MOUSE_BUTTON_LEFT, false))
				_chk(g.state == g.State.DASH, "LMB release -> DASH")
				phase = 1
				t = 0.0
		1:
			if g.state == g.State.PLAY:
				_chk(g.kills == 3, "burst kills 3, got %d" % g.kills)
				phase = 2
				t = 0.0
			elif t > 5.0:
				_chk(false, "dash/burst timeout at state %d" % g.state)
				phase = 9
		2:
			_place(2)
			g.clock_charge = g.CLOCK_TIME
			g._input(_key(KEY_R))
			_chk(g.state == g.State.REWIND, "R -> REWIND")
			phase = 3
			t = 0.0
		3:
			if g.state == g.State.PLAY:
				_chk(g.kills == 5, "rewind kills 5, got %d" % g.kills)
				phase = 6
				t = 0.0
			elif t > 5.0:
				_chk(false, "rewind timeout")
				phase = 9
		6:
			# F1 打开墨笔编辑器（同帧防重入）
			g._input(_key(KEY_F1))
			_chk(g.ink_editor != null, "F1 opens editor")
			_chk(get_tree().paused, "tree paused while editor open")
			if g.ink_editor != null:
				g.ink_editor._input(_key(KEY_F1))
			phase = 7
			t = 0.0
		7:
			if t > 0.1:
				_chk(g.ink_editor == null, "editor closed by F1")
				_chk(not get_tree().paused, "tree unpaused after close")
				phase = 4
				t = 0.0
		4:
			g.player.invuln = 0.0
			g.player.hp = 5.0
			_place(1, true)
			phase = 5
			t = 0.0
		5:
			if g.state == g.State.GAMEOVER:
				_chk(true, "contact -> GAMEOVER")
				phase = 9
			elif t > 5.0:
				_chk(false, "gameover timeout, state %d hp %f" % [g.state, g.player.hp])
				phase = 9
		9:
			for f in fails:
				print("FAIL: ", f)
			print("SMOKE ", "PASS" if fails.is_empty() else "FAIL")
			get_tree().quit(1 if not fails.is_empty() else 0)

func _place(n: int, on_player := false) -> void:
	for i in n:
		var e := Enemy.new()
		e.setup(g.ENEMY_CFGS["blob"].duplicate(), g, null)
		if on_player:
			e.position = g.player.position + Vector2(2, 0)
		else:
			e.position = g.player.position + Vector2(-120.0 + 110.0 * i, 0)
		e.spawn_left = 0.0
		g.add_child(e)
		g.enemies.append(e)

func _btn(idx: int, pressed: bool) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = idx as MouseButton
	ev.pressed = pressed
	return ev

func _key(k: Key) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = k
	ev.pressed = true
	return ev

func _chk(cond: bool, msg: String) -> void:
	print(("ok   " if cond else "BAD  "), msg)
	if not cond:
		fails.append(msg)
