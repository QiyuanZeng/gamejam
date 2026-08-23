extends Node
## 回溯消耗测试：地上留的航道必须恰好是「下一次 R 会走的路」，
## R 用完之后航道链与地面水痕一并清空，不留任何残迹。

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
	if life > 30.0:
		_chk(false, "watchdog at phase %d state %d" % [phase, g.state])
		phase = 9
	match phase:
		0:
			if t > 0.5:
				_slash()
				phase = 1
				t = 0.0
		1:
			if g.state == g.State.PLAY:
				_slash()
				phase = 2
				t = 0.0
			elif t > 8.0:
				_chk(false, "第一刀卡在 state %d" % g.state)
				phase = 9
		2:
			if g.state == g.State.PLAY:
				_chk(g.rewind_hist.size() == 2, "两刀攒出 2 段航道, got %d" % g.rewind_hist.size())
				_chk(g.ink_path.size() > 0, "地上有水痕, pts=%d" % g.ink_path.size())
				g.clock_charge = g.CLOCK_TIME
				g._begin_rewind()
				_chk(g.state == g.State.REWIND, "R -> REWIND, got %d" % g.state)
				_chk(g.rewind_i == g.rewind_hist.size() - 1,
					"从最近一段倒着走, rewind_i=%d" % g.rewind_i)
				phase = 3
				t = 0.0
			elif t > 8.0:
				_chk(false, "第二刀卡在 state %d" % g.state)
				phase = 9
		3:
			if g.state == g.State.REWIND:
				# 回溯途中航道还在（玩家看得见自己正沿哪条路倒走）
				if g.rewind_hist.is_empty():
					_chk(false, "回溯途中航道就被清了")
					phase = 9
				return
			_chk(g.rewind_hist.is_empty(), "回溯走完航道清空, 剩 %d 段" % g.rewind_hist.size())
			_chk(g.ink_path.is_empty(), "回溯走完地面水痕清空, 剩 %d 点" % g.ink_path.size())
			_chk(g.dash_done.is_empty(), "冲刺尾迹清空, 剩 %d 点" % g.dash_done.size())
			phase = 4
			t = 0.0
		4:
			if g.state == g.State.PLAY:
				# 没航道就没得回溯：再按 R 不该进 REWIND
				g.clock_charge = g.CLOCK_TIME
				g._begin_rewind()
				_chk(g.state == g.State.PLAY, "航道空时 R 不触发, state=%d" % g.state)
				# 新斩一刀，航道重新长出来，且只有这一段
				_slash()
				_chk(g.rewind_hist.size() == 1,
					"清空后新斩只留 1 段, got %d" % g.rewind_hist.size())
				phase = 9
			elif t > 6.0:
				_chk(false, "burst 后没回到 PLAY, state %d" % g.state)
				phase = 9
		9:
			for f in fails:
				print("FAIL: %s" % f)
			print("REWIND_CONSUME ", "PASS" if fails.is_empty() else "FAIL")
			get_tree().quit(1 if not fails.is_empty() else 0)

func _slash() -> void:
	g.spawn_timer = 9999.0
	g.state = g.State.PLAY
	g.dial_t = 0.15 * float(g.rewind_hist.size() + 1)
	g.ap = 3.0
	g.last_slash = -99.0
	g._dial_slash()

func _chk(cond: bool, msg: String) -> void:
	if cond:
		print("ok   %s" % msg)
	else:
		print("BAD  %s" % msg)
		fails.append(msg)
