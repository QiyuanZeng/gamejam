extends Node
## 神纹释放全链路模拟：右键起笔 → 按 6px 采样喂点（含 TV 扣费）→ 松笔 → 判定 → 释放。
## 覆盖：精确笔形 / 手写放大抖动 / 乱涂不误触 / 「时」接管状态 / 释放不再收墨钱 /
##       空碑觉醒（够长 + 不撞已有纹 + 掷骰）/ 觉醒当场即释放。

var g: Game
var phase := 0
var t := 0.0
var fails: Array[String] = []
var rng := RandomNumberGenerator.new()

var tank: Enemy
var pre_tv := 0.0
var last_spent := 0.0
var total_t := 0.0
var _tick := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	rng.seed = 20260822
	g = Game.new()
	add_child(g)
	print("[spell_test] 开跑")

func _process(delta: float) -> void:
	t += delta
	total_t += delta
	# 心跳：headless 下每秒报一次现场，卡在哪一阶段一眼看得见
	_tick += 1
	if _tick % 60 == 0:
		print("     ·· 阶段 %d  本阶段 %.1fs  总 %.1fs  state=%d  tv=%.0f" % [
			phase, t, total_t, g.state, g.tv])
	# 看门狗：任何一步卡死都别拖成 headless 挂机，直接把现场打出来收工
	if total_t > 90.0 and phase != 99:
		_chk(false, "整体超时：卡在阶段 %d（本阶段 %.1fs，state=%d）" % [phase, t, g.state])
		_next(99)
	if g != null:
		g.spawn_timer = 9999.0
		g.player.invuln = 999.0
	match phase:
		0:
			if t > 0.5:
				for i in 3:
					_place_at(g.player.position + Vector2(-90.0 + 90.0 * i, -130.0), "melee_mite")
				_reset()
				g.bolts.clear()
				pre_tv = g.tv
				_write(_stroke(SpellMatch.ancient_stroke("thunder"), 1.6, Vector2(300, 160), 0.0), 0.0)
				var s: Dictionary = _skill("thunder")
				_chk(float(s.cd_left) > 0.0, "A 精确「雷」命中 cd=%.1f" % float(s.cd_left))
				_chk(g.bolts.size() > 0, "A 雷霆万钧落下 %d 道雷" % g.bolts.size())
				_chk(g.state == g.State.DASH, "A 释放后仍照常斩击 state=%d" % g.state)
				# 释放本身免费：只该扣笔墨，不该再收施法费。
				# 用 ≥ 而不是 == —— 斩杀会返还时间之力，余额只会比「写前减笔墨」更多。
				_chk(g.tv >= pre_tv - last_spent - 1.0,
					"A 释放不收墨钱：扣 %.0f 笔墨后余 %.0f ≥ %.0f（多出的是斩杀返还）" % [
						last_spent, g.tv, pre_tv - last_spent])
				_next(1)
		1:
			if _wait_play(2):
				pass
		2:
			# 手写：放大 1.8 倍 + 2px 抖动 + 1s 子弹时间流逝
			_reset()
			var raw := _stroke(SpellMatch.ancient_stroke("thunder"), 1.8, Vector2(240, 120), 2.0)
			_write(raw, 1.0)
			var s2: Dictionary = _skill("thunder")
			var feat := SpellMatch.feature(g.ink_path)
			var chk := SpellMatch.check(feat, s2)
			var raw_sim := SpellMatch.similarity(SpellMatch.feature(raw), s2)
			_chk(float(s2.cd_left) > 0.0, "B 手写放大抖动版命中（余 TV %.0f）" % g.tv)
			# 6px 采样门会丢掉近四成点。转正基准若不稳，同一笔的得分会在这里断崖
			_chk(absf(raw_sim - float(chk.sim)) < 0.1,
				"B 采样前后得分稳定：原始 %.1f%% → 入笔 %.1f%%" % [
					raw_sim * 100.0, float(chk.sim) * 100.0])
			print("     [原始 %d 点  入笔 %d 点 %.0fpx  %s]" % [
				raw.size(), g.ink_path.size(), float(feat.get("px", 0.0)), String(chk.reason)])
			_next(3)
		3:
			if _wait_play(4):
				pass
		4:
			# 乱涂：小圆圈（笔长低于觉醒线），不应命中任何神纹、也不该点亮空碑
			_reset()
			var before := _bound_count()
			var circle := PackedVector2Array()
			for i in 33:
				var a := TAU * float(i) / 32.0
				circle.append(Vector2(400, 300) + Vector2(cos(a), sin(a)) * 38.0)
			_write(_densify(circle, 0.0), 0.0)
			_chk(not _any_cd(), "C 乱涂圆圈不误触神纹")
			_chk(_bound_count() == before, "C 短笔不触发觉醒")
			_chk(g.state == g.State.DASH, "C 乱涂仍出斩击 state=%d" % g.state)
			_next(5)
		5:
			if _wait_play(6):
				pass
		6:
			# 「时」：应接管状态直接进回溯，且不再斩击
			_chk(not g.rewind_hist.is_empty(), "D 已有回溯路径 %d 段" % g.rewind_hist.size())
			_place_at(g._point_along(g.rewind_hist[g.rewind_hist.size() - 1], 0.5), "melee_mite")
			_reset()
			_write(_stroke(SpellMatch.ancient_stroke("time"), 1.4, Vector2(300, 220), 1.5), 0.0)
			var s3: Dictionary = _skill("time")
			_chk(float(s3.cd_left) > 0.0, "D 「时」命中")
			_chk(g.state == g.State.REWIND, "D 「时」接管状态 → REWIND，state=%d" % g.state)
			_next(7)
		7:
			if _wait_play(8):
				pass
		8:
			# 觉醒·默认路线（开关关）：一条够长的陌生笔形，概率拉满 → 随机点亮一块空碑并当场施展
			_reset()
			g.bind_chance = 1.0        # 把骰子按死，只验规则不验运气
			g.bind_pick_panel = false
			var probe := SpellMatch.feature(_densify(_awaken_shape(), 0.0))
			var top := float(SpellMatch.best_match(probe, g.skills).top)
			_chk(float(probe.px) >= g.tv_max() * g.BIND_ENERGY_RATIO,
				"E 笔长 %.0fpx 过觉醒线 %.0fpx（上限的 %.0f%%）" % [
					float(probe.px), g.tv_max() * g.BIND_ENERGY_RATIO,
					g.BIND_ENERGY_RATIO * 100.0])
			_chk(top < SpellMatch.BIND_MAX_SIM,
				"E 与已有神纹最高才 %.0f%%，过得了撞形闸 %.0f%%" % [
					top * 100.0, SpellMatch.BIND_MAX_SIM * 100.0])
			var before2 := _bound_count()
			_write(_densify(_awaken_shape(), 0.0), 0.0)
			_chk(not g.bind_panel, "E 开关关着时不弹选碑面板")
			_chk(_bound_count() == before2 + 1, "E 随机点亮 1 块空碑")
			var picked := _last_awakened()
			_chk(not picked.is_empty() and float(picked.cd_left) > 0.0,
				"E 觉醒当场就把「%s」放了出来" % String(picked.get("name", "?")))
			_chk(g.state == g.State.DASH, "E 觉醒那一笔照常补上斩击 state=%d" % g.state)
			_next(9)
		9:
			if _wait_play(10):
				pass
		10:
			# 觉醒·面板路线（开关开）：重开一局神纹录，同一笔形应停下来等玩家挑碑
			g._build_skills()
			_reset()
			g.bind_chance = 1.0
			g.bind_pick_panel = true
			var blank_n := g.blank_slots().size()
			_write(_densify(_awaken_shape(), 0.0), 0.0)
			_chk(g.bind_panel, "E2 开关打开后弹出觉醒选碑面板")
			_chk(g.blank_slots().size() == blank_n, "E2 选之前不预先占碑")
			# 选碑：按 2 取第 2 块空碑 —— 键位跟着 blank_slots 走，不是写死的 idx+2
			var blank: Array = g.blank_slots()
			var target: Dictionary = g.skills[int(blank[1])]
			g._input(_key(KEY_2))
			_chk(not g.bind_panel, "E2 选完关盘")
			_chk(bool(target.bound), "E2 按 2 把纹路刻上第 2 块空碑「%s」" % String(target.name))
			_chk(float(target.cd_left) > 0.0, "E2 选中当场就把「%s」放了出来"
				% String(target.name))
			_chk(g.state == g.State.DASH, "E2 选完补上欠着的那一斩 state=%d" % g.state)
			g.bind_pick_panel = false
			_next(11)
		11:
			if _wait_play(12):
				pass
		12:
			# 复现同一笔形 → 刚觉醒的神纹应释放；且不会再点亮第二块碑
			tank = _place_at(Vector2(1060, 600), "elite_melee")
			_reset()
			var before3 := _bound_count()
			_write(_densify(_awaken_shape(), 0.0), 0.0)
			var s5 := _last_awakened()
			_chk(float(s5.get("cd_left", 0.0)) > 0.0,
				"F 同笔形再画释放「%s」" % String(s5.get("name", "?")))
			_chk(not g.bind_panel, "F 命中已有神纹时不弹盘")
			_chk(_bound_count() == before3, "F 命中已有神纹时不再点亮新碑")
			_next(13)
		13:
			if _wait_play(14):
				pass
		14:
			# 冷却中：同一笔形不该二次释放，只出斩击
			_reset()
			var s6: Dictionary = _skill("thunder")
			s6.cd_left = 5.0
			_write(_stroke(SpellMatch.ancient_stroke("thunder"), 1.6, Vector2(300, 200), 0.0), 0.0)
			_chk(absf(float(s6.cd_left) - 5.0) < 0.2,
				"G 冷却中不重复释放（cd 仍是 %.1f）" % float(s6.cd_left))
			_chk(g.state == g.State.DASH, "G 冷却中仍照常斩击 state=%d" % g.state)
			_next(15)
		15:
			if _wait_play(16):
				pass
		16:
			# 门槛负例：陌生但太短的笔（不到上限 70%）→ 概率拉满也不该觉醒
			_reset()
			g.bind_chance = 1.0
			var short_probe := SpellMatch.feature(_densify(_short_shape(), 0.0))
			_chk(float(short_probe.px) < g.tv_max() * g.BIND_ENERGY_RATIO,
				"H 短笔 %.0fpx 不到觉醒线 %.0fpx" % [
					float(short_probe.px), g.tv_max() * g.BIND_ENERGY_RATIO])
			var before4 := _bound_count()
			_write(_densify(_short_shape(), 0.0), 0.0)
			_chk(not g.bind_panel, "H 墨耗不够 70% 不弹盘")
			_chk(_bound_count() == before4, "H 墨耗不够 70% 不点碑")
			_next(17)
		17:
			if _wait_play(18):
				pass
		18:
			# 半墨起笔：墨本来就不满，画到笔尖干涸 —— 门槛按起笔余额算，这一笔就该够格
			# （旧口径拿 tv_max 当分母，墨不满时玩家画到干也永远凑不满，觉醒等于关死）
			_reset()
			g.tv = g.tv_max() * 0.5
			g.bind_chance = 1.0
			g._build_skills()
			var half0 := g.tv
			var before5 := _bound_count()
			_write(_densify(_awaken_shape(), 0.0), 0.0)
			_chk(g.dry_pen, "I 半墨起笔画到笔尖干涸（余 %.0f）" % g.tv)
			_chk(half0 - g.tv >= half0 * g.BIND_ENERGY_RATIO,
				"I 烧掉起笔余额的 %.0f%%（%.0f / %.0f）" % [
					(half0 - g.tv) / half0 * 100.0, half0 - g.tv, half0])
			_chk(_bound_count() == before5 + 1,
				"I 墨不满也能觉醒，点亮「%s」" % String(_last_awakened().get("name", "?")))
			_next(99)
		99:
			for f in fails:
				print("FAIL: ", f)
			print("SPELL ", "PASS" if fails.is_empty() else "FAIL")
			get_tree().quit(1 if not fails.is_empty() else 0)

# ============================== 驱动helper ==============================

## 按 id 取神纹，不按下标 —— 神纹录顺序变过一次，别再让测试锚死位置。
func _skill(id: String) -> Dictionary:
	for s in g.skills:
		if String(s.id) == id:
			return s
	return {}

func _bound_count() -> int:
	var n := 0
	for s in g.skills:
		if bool(s.bound):
			n += 1
	return n

## 觉醒是随机挑碑的，测试里只能反查「哪块普通神纹已经亮了」。
func _last_awakened() -> Dictionary:
	for s in g.skills:
		if bool(s.bound) and not bool(s.ancient):
			return s
	return {}

## 一个够长的陌生形：闭合三角。
## 圆不行 —— 跟「时」的方框有 64% 相似，太贴撞形闸；折线也不行 —— 「雷」本身就是折线。
## 三角边长 150 时周长约 457px，过得了 350px 的觉醒线，对两个古纹最高才 58%。
func _awaken_shape() -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in 4:
		var a := -PI * 0.5 + TAU * float(i) / 3.0
		out.append(Vector2(560, 320) + Vector2(cos(a), sin(a)) * 88.0)
	return out

## 同样陌生但笔太短的形：半径 30 的圆约 188px，够得着识别门槛却够不着觉醒线。
func _short_shape() -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in 33:
		var a := TAU * float(i) / 32.0
		out.append(Vector2(380, 300) + Vector2(cos(a), sin(a)) * 30.0)
	return out

func _next(p: int) -> void:
	print("     [阶段 %d → %d  用时 %.2fs  state=%d]" % [phase, p, t, g.state])
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
## 顺手把这一笔真实扣掉的墨记进 last_spent —— 用来验「释放本身不额外收钱」。
func _write(path: PackedVector2Array, drain: float) -> void:
	last_spent = 0.0
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
			last_spent += g.tv
			g.tv = 0.0
			g.dry_pen = true
			break
		g.tv -= cost
		last_spent += cost
		g.ink_path.append(path[i])
	var bullet: float = minf(g.BULLET_TV_DRAIN * drain, g.tv)
	g.tv -= bullet
	last_spent += bullet
	g._input(_btn(MOUSE_BUTTON_RIGHT, false))

func _len(path: PackedVector2Array) -> float:
	var s := 0.0
	for i in path.size() - 1:
		s += path[i].distance_to(path[i + 1])
	return s

func _place_at(pos: Vector2, kind: String) -> Enemy:
	var e := Enemy.new()
	e.setup(EnemyDB.cfg(kind), g, null)
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
