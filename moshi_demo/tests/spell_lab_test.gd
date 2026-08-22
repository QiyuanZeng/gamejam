extends Node
## 咒语调试台冒烟：F2 开关 / 无限墨不扣 TV / 消耗折算 / 匹配度判定 / 录入笔形与战局隔离。

var g: Game
var lab
var phase := 0
var t := 0.0
var fails: Array[String] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	g = Game.new()
	add_child(g)

func _process(delta: float) -> void:
	t += delta
	if g != null:
		g.spawn_timer = 9999.0
	match phase:
		0:
			if t > 0.3:
				g._input(_key(KEY_F2))
				_next(1)
		1:
			if g.spell_lab != null:
				lab = g.spell_lab
				_chk(true, "F2 打开调试台")
				_chk(get_tree().paused, "调试台打开时暂停战局")
				_chk(lab.skills.size() == 8, "技能表 8 条，实得 %d" % lab.skills.size())
				_next(2)
			elif t > 1.0:
				_chk(false, "F2 打开调试台")
				_next(99)
		2:
			# 精确「雷」笔形放大 3 倍：应满格命中，且不扣真实 TV
			var pre_tv: float = g.tv
			lab.strokes.append(_scaled("thunder", 3.0, Vector2(60, 60)))
			lab.last_t = 0.6
			var feat := SpellMatch.feature(lab.active_path())
			var chk := SpellMatch.check(feat, _skill("thunder"))
			_chk(bool(chk.ok), "精确「雷」命中：%s" % String(chk.reason))
			_chk(float(chk.sim) >= 0.99, "形状相似度 %.0f%%" % (float(chk.sim) * 100.0))
			_chk(absf(g.tv - pre_tv) < 0.01, "无限墨：真实 TV 未被扣（%.0f）" % g.tv)
			var px := float(feat.px)
			var total: float = px * g.TV_COST_PER_PX + g.BULLET_TV_DRAIN * lab.elapsed()
			_chk(absf(lab.elapsed() - 0.6) < 0.001, "书写耗时读数 %.2fs" % lab.elapsed())
			_chk(total > px, "合计消耗含子弹流逝：%.0f > 笔墨 %.0f" % [total, px])
			print("     [笔长 %.0fpx  合计 %.0f 时  上限 %.0f]" % [px, total, lab.tv_max()])
			_next(3)
		3:
			if t > 0.1:
				# 乱涂：任何技能都不该命中
				lab.strokes.clear()
				var circle := PackedVector2Array()
				for i in 41:
					var a := TAU * float(i) / 40.0
					circle.append(Vector2(300, 280) + Vector2(cos(a), sin(a)) * 120.0)
				lab.strokes.append(circle)
				var feat2 := SpellMatch.feature(lab.active_path())
				var any := false
				for s in lab.skills:
					if bool(SpellMatch.check(feat2, s).ok):
						any = true
				_chk(not any, "乱涂圆圈对 8 技能全不命中")
				_next(4)
		4:
			# 录入：把当前笔形绑进第 3 个技能，且不污染战局技能表
			lab._learn(2)
			var s: Dictionary = lab.skills[2]
			var gs: Dictionary = g.skills[2]
			_chk(bool(s.bound), "按 3 录入笔形到「%s」" % String(s.name))
			_chk(not bool(gs.bound), "录入不污染战局技能表")
			var chk2 := SpellMatch.check(SpellMatch.feature(lab.active_path()), s)
			_chk(bool(chk2.ok), "录入后同笔形自命中：%s" % String(chk2.reason))
			_next(5)
		5:
			lab._input(_key(KEY_2))
			_chk(lab.ghost_id == "thunder", "2 键切换「雷」参照描摹")
			lab._input(_key(KEY_C))
			_chk(lab.strokes.is_empty(), "C 清空画布")
			_next(6)
		6:
			if t > 0.35:
				lab._input(_key(KEY_F2, false))
				lab._input(_key(KEY_F2))
				_next(7)
		7:
			if t > 0.2:
				_chk(g.spell_lab == null, "F2 关闭调试台")
				_chk(not get_tree().paused, "关闭后恢复战局")
				_next(99)
		99:
			for f in fails:
				print("FAIL: ", f)
			print("SPELLLAB ", "PASS" if fails.is_empty() else "FAIL")
			get_tree().quit(1 if not fails.is_empty() else 0)

## 按 id 取台内神纹，不锚死下标 —— 神纹录顺序调整过一次。
func _skill(id: String) -> Dictionary:
	for s in lab.skills:
		if String(s.id) == id:
			return s
	return {}

func _next(p: int) -> void:
	phase = p
	t = 0.0

func _scaled(id: String, k: float, org: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in SpellMatch.ancient_stroke(id):
		out.append(p * k + org)
	return out

func _key(k: Key, pressed := true) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = k
	ev.pressed = pressed
	return ev

func _chk(cond: bool, msg: String) -> void:
	print(("ok   " if cond else "BAD  "), msg)
	if not cond:
		fails.append(msg)
