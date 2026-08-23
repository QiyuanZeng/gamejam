extends Node
## 墨尽不收笔：右键写到墨干后，不再自动斩击，而是继续挂在子弹时间里等玩家松手。
## 干涸期间不再落笔（ink_path 不增点），松开右键才沿已画轨迹冲刺。

var g: Game
var phase := 0
var t := 0.0
var total := 0.0
var fails: Array[String] = []
var pts0 := 0
var dry_wait := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	g = Game.new()
	add_child(g)

func _process(delta: float) -> void:
	t += delta
	total += delta
	if total > 20.0:
		_chk(false, "看门狗超时于阶段 %d，state=%d" % [phase, g.state])
		phase = 9
	if g != null:
		g.spawn_timer = 9999.0
	match phase:
		0:
			if t > 0.5:
				g._input(_btn(MOUSE_BUTTON_RIGHT, true))
				_chk(g.state == g.State.SPELL, "右键按下 -> SPELL, got %d" % g.state)
				var p: Vector2 = g.player.position
				g.ink_path = PackedVector2Array([p, p + Vector2(100, 0), p + Vector2(250, 0)])
				g.ink_ages = PackedFloat32Array([0.0, 0.0, 0.0])
				g.dry_pen = false
				g.tv = 15.0          # BULLET_TV_DRAIN=30/s → 约 0.5s 见底
				_next(1)
		1:
			if g.dry_pen:
				_chk(g.state == g.State.SPELL,
					"墨尽后不自动收笔，仍在 SPELL, got %d" % g.state)
				_chk(g.tv <= 0.01, "墨水清零, tv=%.2f" % g.tv)
				pts0 = g.ink_path.size()
				dry_wait = 0.0
				_next(2)
			elif t > 3.0:
				_chk(false, "等墨干超时, tv=%.2f" % g.tv)
				_next(9)
		2:
			dry_wait += delta
			if g.state != g.State.SPELL:
				_chk(false, "干涸期间被强行收笔, state=%d" % g.state)
				_next(9)
			elif dry_wait > 1.0:
				_chk(g.state == g.State.SPELL, "按住不放持续 1s 仍在书写态")
				_chk(is_equal_approx(g.enemy_speed_factor(), g.BULLET_FACTOR),
					"干涸期间仍是子弹时间, f=%.2f" % g.enemy_speed_factor())
				_chk(g.ink_path.size() == pts0,
					"干涸后不再落笔, %d -> %d" % [pts0, g.ink_path.size()])
				g._input(_btn(MOUSE_BUTTON_RIGHT, false))
				_chk(g.state == g.State.DASH, "松开右键才冲刺, got %d" % g.state)
				_chk(g.dash_pts.size() >= 2, "沿已画轨迹走, pts=%d" % g.dash_pts.size())
				_next(9)
		9:
			for f in fails:
				print("FAIL: ", f)
			print("DRY_PEN_HOLD ", "PASS" if fails.is_empty() else "FAIL")
			get_tree().quit(1 if not fails.is_empty() else 0)

func _next(p: int) -> void:
	phase = p
	t = 0.0

func _btn(idx: int, pressed: bool) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = idx as MouseButton
	ev.pressed = pressed
	return ev

func _chk(cond: bool, msg: String) -> void:
	if cond:
		print("ok   ", msg)
	else:
		print("BAD  ", msg)
		fails.append(msg)
