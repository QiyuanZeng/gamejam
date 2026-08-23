extends Node
## 实机刷怪校验：跑真实主循环 + 真实波表（data/balance.tres 的 waves），确认波表配置没配歪、
## 八种怪都能刷出来、四类行为都真正跑起来、局内无时限、敌弹致死直接结算。
## 标签：WAVE_LIVE PASS / FAIL

var g: Game
var phase := 0
var t := 0.0
var total := 0.0
var fails: Array[String] = []

var seen_ids := {}
var seen_behaviors := {}
var saw_elite := false
var saw_bullet := false
var saw_windup := false
var saw_dash := false
var peak := 0
var spawned_all: Array = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	g = Game.new()
	add_child(g)

func _process(delta: float) -> void:
	t += delta
	total += delta
	if total > 45.0:
		_chk(false, "watchdog timeout at phase %d" % phase)
		phase = 9
	if g == null:
		return
	match phase:
		0:
			if t > 0.3:
				g.spawn_timer = 9999.0
				g.player.invuln = 999.0
				_test_wave_table()
				_spawn_every_id()
				_next(1)
		1:
			# 确定性覆盖：每种 id 各来一只，跑够时间让远程开火、冲锋蓄力
			g.spawn_timer = 9999.0
			g.player.invuln = 999.0
			_scan()
			if t > 3.0:
				_chk(spawned_all.size() == EnemyDB.ids().size(),
					"每种 id 都能生成：%d / %d" % [spawned_all.size(), EnemyDB.ids().size()])
				var alive := 0
				for e in spawned_all:
					if is_instance_valid(e) and not e.dead:
						alive += 1
				_chk(alive == spawned_all.size(), "生成的怪全部存活 %d / %d" % [alive, spawned_all.size()])
				_chk(saw_bullet, "远程小兵真的开了火")
				_chk(saw_windup, "冲锋小兵真的进了蓄力")
				_chk(saw_dash, "冲锋小兵真的冲了出去")
				_clear()
				g.run_time = 120.0
				g.spawn_timer = 0.0
				# 统计量清零，phase 2 只认真实波表刷出来的
				seen_ids.clear()
				seen_behaviors.clear()
				saw_elite = false
				_next(2)
		2:
			# 真实波表刷怪：钉在 120s，也就是永久平台期（末段）
			g.run_time = 120.0
			g.player.invuln = 999.0
			_scan()
			peak = maxi(peak, g.enemies.size())
			_farm_splitter()
			if t > 12.0:
				_chk(g.state != g.State.GAMEOVER, "跑到 120s 也不结算：本局没有时限")
				_chk(g._wave_seg() == WaveDB.final_seg(),
					"120s 时用的是永久平台期那一段（%s）" % g._wave_seg().id)
				_chk(g.enemies.size() > 0, "波表持续刷出怪，场上 %d" % g.enemies.size())
				_chk(peak <= g.max_enemies, "在场数没越上限 %d <= %d" % [peak, g.max_enemies])
				_chk(peak > 20, "提速后场面压得住人，峰值 %d 只" % peak)
				_chk(seen_ids.size() >= 5, "刷出 %d 种怪：%s" % [seen_ids.size(), str(seen_ids.keys())])
				for b in [EnemyData.Behavior.MELEE, EnemyData.Behavior.RANGED,
						EnemyData.Behavior.CHARGER, EnemyData.Behavior.SPLITTER]:
					_chk(seen_behaviors.has(b), "行为 %d 出现在真实波表里" % b)
				_chk(saw_elite, "精英怪刷得出来")
				_chk(seen_ids.has("splitter_bomber_shard"), "分裂子体在实机里生成")
				_clear()
				_next(3)
		3:
			# 敌弹致死直接结算（时滞已移除）
			g.player.invuln = 0.0
			g.player.hp = 1.0
			g.spawn_enemy_bullet(g.player.position, Vector2.RIGHT, {"bullet_dmg": 99.0})
			g._update_enemy_bullets(0.016, 1.0)
			_chk(g.player.hp <= 0.0, "敌弹打空玩家血量")
			_chk(g.state == g.State.GAMEOVER,
				"致死后直接结算，当前 %d" % g.state)
			_next(9)
		9:
			for f in fails:
				print("FAIL: ", f)
			print("WAVE_LIVE ", "PASS" if fails.is_empty() else "FAIL")
			get_tree().quit(1 if not fails.is_empty() else 0)

## 波表配置体检：路径、段序、提速数值、mix 里的 id 是否都真实存在
func _test_wave_table() -> void:
	var segs := WaveDB.all()
	_chk(segs.size() >= 5, "WaveDB 载到 %d 段波表" % segs.size())
	var errs := WaveDB.validate()
	for e in errs:
		_chk(false, "波表配置有问题：%s" % String(e))
	if errs.is_empty():
		_chk(true, "波表体检干净：权重和为 1、mix 里的 id 都在 EnemyDB 里")
	# 段序必须按 until_time 升序
	var ordered := true
	for i in range(1, segs.size()):
		if segs[i].until_time < segs[i - 1].until_time:
			ordered = false
	_chk(ordered, "波表按 until_time 排好了序")
	# 提速到位：末段 0.18 秒一只、场上 64 只
	var last: WaveData = WaveDB.final_seg()
	_chk(is_equal_approx(last.interval, 0.18), "末段 interval 提速到 %.2f" % last.interval)
	_chk(last.cap == 64, "末段 cap 拉到 %d" % last.cap)
	# 首段必须是纯近战开局
	var first: WaveData = segs[0]
	_chk(first.mix.size() == 1 and first.mix.has("melee_mite"), "开局段只有影蚋")
	# 时段查询：几个关键时间点落在预期的段上
	_chk(WaveDB.seg_for(1.0).id == "seg1_opening", "1s 走开局段")
	_chk(WaveDB.seg_for(8.0).id == "seg2_rush", "8s 走冲锋段")
	_chk(WaveDB.seg_for(15.0).id == "seg3_ranged", "15s 走远程段")
	_chk(WaveDB.seg_for(24.0).id == "seg4_elite", "24s 走精英段")
	_chk(WaveDB.seg_for(999.0).id == "seg5_plateau", "999s 仍走永久平台期")

func _spawn_every_id() -> void:
	var ids := EnemyDB.ids()
	var n := ids.size()
	for i in n:
		# 摆在冲锋触发范围内（<600），远程也在攻击距离内（<420）
		var a := TAU * float(i) / float(n)
		var e := g.spawn_enemy_at(String(ids[i]), g.player.position + Vector2(cos(a), sin(a)) * 380.0)
		if e == null:
			_chk(false, "spawn_enemy_at 生成失败 id=%s" % String(ids[i]))
			continue
		e.spawn_left = 0.0
		e.hp = 9999.0        # 别被自己人的爆炸炸死，保证存活断言干净
		spawned_all.append(e)

func _scan() -> void:
	if g.enemy_bullets.size() > 0:
		saw_bullet = true
	for e in g.enemies:
		var id := String(e.cfg.get("id", ""))
		if id != "":
			seen_ids[id] = true
		seen_behaviors[int(e.cfg.get("behavior", 0))] = true
		if bool(e.cfg.get("is_elite", false)):
			saw_elite = true
		if e.charge_state == "windup":
			saw_windup = true
		elif e.charge_state == "dash":
			saw_dash = true

## 场上一有分裂怪就宰掉，确认子体在实机里真的生得出来
func _farm_splitter() -> void:
	for e in g.enemies.duplicate():
		if e.dead or e.spawn_left > 0.0:
			continue
		if String(e.cfg.get("id", "")) == "splitter_bomber":
			g._kill_enemy(e)
			return

func _clear() -> void:
	for e in g.enemies.duplicate():
		e.dead = true
		e.queue_free()
	g.enemies.clear()
	g.enemy_bullets.clear()
	g.blasts.clear()
	spawned_all.clear()

func _next(p: int) -> void:
	phase = p
	t = 0.0

func _chk(cond: bool, msg: String) -> void:
	if cond:
		print("ok  ", msg)
	else:
		print("BAD ", msg)
		fails.append(msg)
