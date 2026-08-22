extends Node
## 冒烟测试 v0.3：左键时钟斩 → BURST → R 回溯 → 右键子弹时间 → 受击不死亡 → 时限结算。
## headless 直调 Game 内部 API + 伪造输入事件，确定性断言。
## 运行：godot --headless --path demo_test tests/smoke.tscn

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
				# 左键时钟斩：指针打到 0°(+x)，沿线放 3 只 fast（HP18 < 斩伤20）
				g.swing_deg = 0.0
				_place(3, "fast", Vector2(60.0, 0))
				g._input(_btn(MOUSE_BUTTON_LEFT, true))
				_chk(g.state == g.State.DASH, "LMB click -> DASH, got %d" % g.state)
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
			# R 回溯：重放斩击路径，路径上再放 2 只
			g.clock_charge = g.CLOCK_TIME
			_place(2, "fast", Vector2(-260.0, 0))
			g._input(_key(KEY_R))
			_chk(g.state == g.State.REWIND, "R -> REWIND, got %d" % g.state)
			phase = 3
			t = 0.0
		3:
			if g.state == g.State.PLAY:
				_chk(g.kills == 5, "rewind kills 5, got %d" % g.kills)
				_chk(absf(g.score_mult - 1.5) < 0.001,
					"BUG-10: 5 kills -> mult 1.5, got %.2f" % g.score_mult)
				phase = 10
				t = 0.0
			elif t > 5.0:
				_chk(false, "rewind timeout")
				phase = 9
		10:
			# BUG-07 连锁：线上斩杀 boom A，垂直偏离的 boom B / blob C 只能靠爆炸波及
			g.swing_deg = 0.0
			_place(1, "boom", Vector2(70.0, 0))
			_place_off("boom", Vector2(70.0, 90.0))
			_place_off("blob", Vector2(70.0, 180.0))
			g._input(_btn(MOUSE_BUTTON_LEFT, true))
			phase = 11
			t = 0.0
		11:
			if t > 0.6:
				_chk(g.kills == 8, "BUG-07: boom chain kills 8, got %d" % g.kills)
				phase = 4
				t = 0.0
		4:
			# task-8 子弹时间：右键进 SPELL_DRAW，全局 0.3 倍速；松开恢复
			g.time_value = 100.0
			g._input(_btn(MOUSE_BUTTON_RIGHT, true))
			_chk(g.state == g.State.SPELL_DRAW, "RMB hold -> SPELL_DRAW, got %d" % g.state)
			_chk(absf(Engine.time_scale - g.SPELL_TIMESCALE) < 0.001,
				"time_scale %.2f == %.2f" % [Engine.time_scale, g.SPELL_TIMESCALE])
			g._input(_btn(MOUSE_BUTTON_RIGHT, false))
			_chk(g.state == g.State.PLAY, "RMB release -> PLAY, got %d" % g.state)
			_chk(absf(Engine.time_scale - 1.0) < 0.001, "time_scale restored 1.0")
			phase = 5
			t = 0.0
		5:
			# P0 BUG-01：受击不死亡，扣充能 + 清 combo（充能设满防自然回复干扰断言）
			g.player.invuln = 0.0
			g.clock_charge = g.CLOCK_TIME
			g.combo = 9
			_place(1, "blob", Vector2.ZERO)
			phase = 6
			t = 0.0
		6:
			if t > 0.3:
				_chk(g.state != g.State.GAMEOVER, "hit does NOT gameover")
				# 满充 25 - 8 惩罚 = 17，随后 0.3s 自然回复 ≈ +0.3
				_chk(g.clock_charge >= 17.0 and g.clock_charge <= 17.5,
					"charge 25-8+regen in [17,17.5], got %.2f" % g.clock_charge)
				_chk(g.combo == 0, "combo cleared on hit")
				_chk(absf(g.score_mult - 1.0) < 0.001,
					"BUG-10: hit decays mult 1.5*0.5->floor 1.0, got %.2f" % g.score_mult)
				_chk(g.player.hp == g.player.max_hp, "hp untouched (no death mechanic)")
				# BUG-06：时限归零出结算
				g.round_timer = 0.02
				phase = 7
				t = 0.0
		7:
			if g.state == g.State.GAMEOVER:
				_chk(absf(Engine.time_scale - 1.0) < 0.001, "time_scale 1.0 at gameover")
				phase = 9
			elif t > 3.0:
				_chk(false, "gameover timeout, state %d" % g.state)
				phase = 9
		9:
			for f in fails:
				print("FAIL: ", f)
			print("SMOKE ", "PASS" if fails.is_empty() else "FAIL")
			get_tree().quit(1 if not fails.is_empty() else 0)

## 沿玩家 +x 斩击线放 n 只怪（offset 为相对玩家位置的起点，横向均布 80px）
func _place(n: int, cfg_name: String, offset: Vector2) -> void:
	for i in n:
		var e := Enemy.new()
		e.setup(g.ENEMY_CFGS[cfg_name].duplicate(), g, null)
		e.position = g.player.position + offset + Vector2(80.0 * i, 0)
		e.spawn_left = 0.0
		g.add_child(e)
		g.enemies.append(e)

## 相对玩家位置直接放 1 只怪（不做横向均布）
func _place_off(cfg_name: String, offset: Vector2) -> void:
	var e := Enemy.new()
	e.setup(g.ENEMY_CFGS[cfg_name].duplicate(), g, null)
	e.position = g.player.position + offset
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
