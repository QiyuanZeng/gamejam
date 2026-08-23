extends Node
## 五道神纹的效果专项：逐个直调 _cast，验落雷/地震/树人/水浪/剑阵确实打到人。
## 只管效果层，不走笔形识别 —— 识别那条链路由 spell_test 与 qdollar_test 覆盖。

var g: Game
var phase := 0
var t := 0.0
var total_t := 0.0
var _tick := 0
var ent_d0 := 0.0                # 树人刚召出来时离敌人多远，用来验它有没有往前挪
var moved := false               # 地震阶段是否已经把玩家挪过位（靶子只补一次）
var fails: Array[String] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	g = Game.new()
	add_child(g)
	print("[skill_fx_test] 开跑：雷霆万钧/山崩地裂/妖木精灵/水漫金山/无限剑阵")

func _process(delta: float) -> void:
	t += delta
	total_t += delta
	_tick += 1
	if _tick % 60 == 0 and g != null:
		print("     ·· 阶段 %d  本阶段 %.1fs  总 %.1fs  场上 %d 怪  余血 %.0f" % [
			phase, t, total_t, g.enemies.size(), _total_hp()])
	if total_t > 90.0 and phase != 99:
		_chk(false, "整体超时：卡在阶段 %d（本阶段 %.1fs）" % [phase, t])
		_next(99)
	if g == null:
		return
	g.spawn_timer = 9999.0
	g.player.invuln = 999.0
	match phase:
		0:
			if t > 0.4:
				g.player.position = Vector2(576, 324)
				_next(1)
		1:
			# 雷霆万钧：随机挑几个目标劈，每道雷带小范围溅射
			_field(10, 120.0)
			var hp0 := _total_hp()
			g._cast("thunder")
			_chk(g.bolts.size() > 0, "雷霆万钧落下 %d 道雷" % g.bolts.size())
			_chk(g.bolts.size() <= g.THUNDER_BOLTS,
				"落雷不超过 %d 道（实得 %d）" % [g.THUNDER_BOLTS, g.bolts.size()])
			_chk(_total_hp() < hp0, "雷击造成伤害 %.0f" % (hp0 - _total_hp()))
			_next(2)
		2:
			# 山崩地裂：6 轮，每 0.5s 一轮，震源跟着玩家走
			_clear()
			_field(6, 90.0)
			g._cast("quake")
			_chk(g.quakes.size() == 1, "山崩地裂起 1 组地震")
			_chk(int(g.quakes[0].left) == g.QUAKE_WAVES,
				"待放 %d 轮（实得 %d）" % [g.QUAKE_WAVES, int(g.quakes[0].left)])
			_next(3)
		3:
			# 跑够 6 轮的时长，途中把玩家挪走验「跟随」：新震源应打到新位置的怪
			# 只补一次靶子 —— 每帧补的话新怪会源源不断盖过地震的战果，断言变成看运气
			if not moved and t > 0.2 and not g.quakes.is_empty():
				moved = true
				g.player.position = Vector2(200, 200)
				_place_at(Vector2(230, 210))
			if t > float(g.QUAKE_WAVES) * g.QUAKE_GAP + 0.3:
				_chk(g.quakes.is_empty(), "6 轮放完自动收场")
				_chk(_total_hp() < 6.0 * 10.0, "地震把场上怪打残（余血 %.0f）" % _total_hp())
				_next(4)
		4:
			# 妖木精灵：召 4 个树人，会自己扑向敌人
			_clear()
			g.player.position = Vector2(576, 324)
			_place_at(Vector2(900, 500))
			g._cast("ent")
			_chk(g.ents.size() == g.ENT_COUNT, "召出 %d 个树人" % g.ents.size())
			ent_d0 = _ent_dist(Vector2(900, 500))
			_next(5)
		5:
			if t > 1.6:
				_chk(g.ents.size() == g.ENT_COUNT, "树人存活期内不消失")
				# 树人速度有限，1.6s 未必够摸到敌人，只验它确实在往人身上凑
				var d1 := _ent_dist(Vector2(900, 500))
				_chk(d1 < ent_d0 - 60.0,
					"树人自由行动、朝敌人靠拢（%.0f → %.0f px）" % [ent_d0, d1])
				_next(6)
		6:
			# 水漫金山：八向水浪，环绕一圈的怪应当全被扫到
			_clear()
			for i in 8:
				var a := TAU * float(i) / 8.0
				_place_at(g.player.position + Vector2(cos(a), sin(a)) * 200.0)
			var hp1 := _total_hp()
			g._cast("flood")
			_chk(g.floods.size() == g.FLOOD_DIRS, "推出 %d 道水浪" % g.floods.size())
			_next(7)
		7:
			# 射程 640 / 速度 540 ≈ 1.19s，但斩杀顿帧会冻住驻场效果的推进，多给半秒余量
			if t > g.FLOOD_RANGE / g.FLOOD_SPEED + 0.5:
				_chk(g.floods.is_empty(), "水浪走完射程自动消散")
				_chk(_total_hp() < 8.0 * 10.0, "八向水浪打到环阵（余血 %.0f）" % _total_hp())
				_next(10)
		10:
			# 无限剑阵：内外两圈同时挂上
			_clear()
			g.player.position = Vector2(576, 324)
			for i in 12:
				var a := TAU * float(i) / 12.0
				_place_at(g.player.position + Vector2(cos(a), sin(a)) * g.SWORD_R_OUT)
			g._cast("swords")
			_chk(g.swords.size() == g.SWORD_INNER + g.SWORD_OUTER,
				"内 %d + 外 %d = %d 把剑" % [
					g.SWORD_INNER, g.SWORD_OUTER, g.swords.size()])
			_next(11)
		11:
			if t > g.SWORD_FALL + 0.5:
				_chk(g.swords.is_empty(), "落剑结算完自动清空")
				_chk(_total_hp() < 12.0 * 10.0, "外圈落剑砸中环阵（余血 %.0f）" % _total_hp())
				_next(99)
		99:
			for f in fails:
				print("FAIL: ", f)
			print("SKILLFX ", "PASS" if fails.is_empty() else "FAIL")
			get_tree().quit(1 if not fails.is_empty() else 0)

# ============================== helper ==============================

func _next(p: int) -> void:
	print("     [阶段 %d → %d  用时 %.2fs]" % [phase, p, t])
	phase = p
	t = 0.0

## 清场：连带把上一轮的驻场效果收干净，免得串味
func _clear() -> void:
	for e in g.enemies.duplicate():
		e.dead = true
		g.enemies.erase(e)
		e.queue_free()
	g.quakes.clear()
	g.ents.clear()
	g.floods.clear()
	g.swords.clear()
	g.bolts.clear()
	g.player.visible = true

## 在玩家周围摆一圈血厚不掉的靶子（用 blob 的 10 血，方便按总血量断言）
func _field(n: int, r: float) -> void:
	_clear()
	for i in n:
		var a := TAU * float(i) / float(n)
		_place_at(g.player.position + Vector2(cos(a), sin(a)) * r)

func _place_at(pos: Vector2) -> Enemy:
	var e := Enemy.new()
	e.setup(EnemyDB.cfg("melee_mite"), g, null)
	e.position = pos
	e.spawn_left = 0.0
	e.hp = 10.0
	g.add_child(e)
	g.enemies.append(e)
	return e

func _total_hp() -> float:
	var s := 0.0
	for e in g.enemies:
		if not e.dead:
			s += e.hp
	return s

## 离目标最近的那个树人有多远
func _ent_dist(target: Vector2) -> float:
	var best := 99999.0
	for e in g.ents:
		best = minf(best, e.pos.distance_to(target))
	return best

func _chk(cond: bool, msg: String) -> void:
	print(("ok   " if cond else "BAD  "), msg)
	if not cond:
		fails.append(msg)
