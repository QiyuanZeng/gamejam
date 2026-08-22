extends Node
## 怪物重构回归测试：配置表加载、四类行为、分裂、精英，以及技能命中链路不回退。
## 标签：ENEMY_REFACTOR PASS / FAIL

var g: Game
var phase := 0
var t := 0.0
var total := 0.0
var fails: Array[String] = []

var subject: Enemy
var mark_d0 := 0.0
var charge_p0 := 0.0
var charge_dir0 := Vector2.ZERO
var charge_org := Vector2.ZERO

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	g = Game.new()
	add_child(g)

func _process(delta: float) -> void:
	t += delta
	total += delta
	if total > 30.0:
		_chk(false, "watchdog timeout at phase %d" % phase)
		phase = 99
	if g != null:
		g.spawn_timer = 9999.0        # 关掉自然生成，隔离测试环境
		if g.player != null:
			g.player.invuln = 999.0   # 玩家吃不到伤害，敌弹不会被消耗掉
	match phase:
		0:
			if t > 0.3:
				_test_config()
				_clear()
				subject = g.spawn_enemy_at("melee_mite", g.player.position + Vector2(400, 0))
				subject.spawn_left = 0.0
				mark_d0 = subject.position.distance_to(g.player.position)
				_next(1)
		1:
			if t > 0.5:
				_chk(subject.position.distance_to(g.player.position) < mark_d0 - 20.0,
					"近战兵朝玩家推进，剩余 %.1f（起始 %.1f）"
					% [subject.position.distance_to(g.player.position), mark_d0])
				_setup_ranged()
				_next(2)
		2:
			if t > 0.4:
				_chk(g.enemy_bullets.size() > 0,
					"远程兵开火，弹数 %d" % g.enemy_bullets.size())
				_chk(subject.velocity.length() < 30.0,
					"远程兵到攻击距离后停步，速度 %.1f" % subject.velocity.length())
				_test_bullet_clear()
				_setup_charger()
				_next(3)
		3:
			if subject.charge_state == "windup":
				_chk(true, "冲锋兵进范围后停步蓄力")
				charge_p0 = subject.charge_progress()
				charge_dir0 = subject.charge_dir
				# 红线已经出来了：这时候把玩家挪到侧面，方向不该再跟过去
				g.player.position += Vector2(0, -420)
				_next(4)
			elif t > 2.0:
				_chk(false, "冲锋兵未进入蓄力，当前 %s" % subject.charge_state)
				_next(9)
		4:
			if t > 0.12:
				var p := subject.charge_progress()
				_chk(p > charge_p0 and p > 0.0,
					"预警随蓄力充能：%.2f → %.2f" % [charge_p0, p])
				_chk(subject.charge_dir.is_equal_approx(charge_dir0),
					"红线出现后方向锁死：玩家挪走也不转向（%.3f 弧度偏差）"
					% absf(subject.charge_dir.angle_to(charge_dir0)))
				var to_now: Vector2 = g.player.position - subject.position
				_chk(absf(to_now.normalized().angle_to(charge_dir0)) > 0.3,
					"玩家确实挪到了别处，这条断言才有意义")
				_next(5)
		5:
			if t > 0.6:
				_chk(subject.charge_state == "dash" or subject.charge_state == "recover",
					"蓄满后进入冲锋，当前 %s" % subject.charge_state)
				_chk(subject.position.distance_to(charge_org) > 50.0,
					"冲锋产生位移 %.1f" % subject.position.distance_to(charge_org))
				_clear()
				_test_split()
				_test_skill_hit()
				_next(9)
		9:
			for f in fails:
				print("FAIL: ", f)
			print("ENEMY_REFACTOR ", "PASS" if fails.is_empty() else "FAIL")
			get_tree().quit(1 if not fails.is_empty() else 0)
		99:
			phase = 9

# ── 配置表 ──────────────────────────────────────────────────────────
func _test_config() -> void:
	var want := ["melee_mite", "ranged_crystal", "charger_fast", "splitter_bomber",
		"splitter_bomber_shard", "elite_melee", "elite_ranged", "elite_charger",
		"elite_splitter"]
	for id in want:
		_chk(EnemyDB.has(id), "EnemyDB 载到 %s" % id)
	_chk(EnemyDB.ids().size() == want.size(),
		"怪表只剩 %d 份配置（期望 %d）" % [EnemyDB.ids().size(), want.size()])
	_chk(not EnemyDB.has("boss_wuming") and not EnemyDB.has("melee_blob")
		and not EnemyDB.has("elite_tank"), "旧的 BOSS / 重复近战 / 独立贴图精英已清干净")
	var b: EnemyData = EnemyDB.get_data("melee_mite")
	_chk(b != null and b.behavior == EnemyData.Behavior.MELEE, "melee_mite 为近战行为")
	var r: EnemyData = EnemyDB.get_data("ranged_crystal")
	_chk(r != null and r.behavior == EnemyData.Behavior.RANGED, "ranged_crystal 为远程行为")
	var c: EnemyData = EnemyDB.get_data("charger_fast")
	_chk(c != null and c.behavior == EnemyData.Behavior.CHARGER, "charger_fast 为冲锋行为")
	_chk(c != null and c.charge_range == 600.0 and c.charge_dist == 900.0
		and c.charge_time == 2.0, "冲锋数值 600/900/2s 与需求一致")
	var s: EnemyData = EnemyDB.get_data("splitter_bomber")
	_chk(s != null and s.behavior == EnemyData.Behavior.SPLITTER, "splitter_bomber 为分裂行为")
	_chk(s != null and s.split_count == 2 and s.split_child_id == "splitter_bomber_shard",
		"分裂怪炸出 2 只子体")
	var kid: EnemyData = EnemyDB.get_data("splitter_bomber_shard")
	_chk(kid != null and kid.split_child_id == "", "子体不再分裂")
	_chk(kid != null and s != null and kid.hp < s.hp,
		"子体血量更低 %.0f < %.0f" % [kid.hp if kid else 0.0, s.hp if s else 0.0])
	_chk(kid != null and s != null and kid.tex == s.tex, "子体复用本体贴图")
	_chk(kid != null and s != null and kid.tex_target < s.tex_target,
		"子体贴图按比例缩小 %.0f < %.0f"
		% [kid.tex_target if kid else 0.0, s.tex_target if s else 0.0])
	_test_one_per_behavior()
	_test_art_reuse()
	# cfg 兼容视图：技能命中读的键一个都不能少
	var e: EnemyData = EnemyDB.get_data("elite_melee")
	_chk(e != null and e.is_elite and e.scale_mul > 1.0,
		"精英怪放大 %.2fx" % (e.scale_mul if e else 0.0))
	_chk(e != null and e.tint != Color(1, 1, 1, 1), "精英怪改色")
	var cfg := EnemyDB.cfg("elite_melee")
	for k in ["radius", "dmg", "type", "score", "coin", "tv", "hp", "speed"]:
		_chk(cfg.has(k), "cfg 兼容视图保留键 %s" % k)
	_chk(is_equal_approx(float(cfg.radius), e.radius * e.scale_mul),
		"精英半径按倍率放大 %.1f" % float(cfg.radius))

## 四类行为各只留一只基础怪（精英与分裂子体不计）。
func _test_one_per_behavior() -> void:
	var count := {}
	for id in EnemyDB.ids():
		var d: EnemyData = EnemyDB.get_data(id)
		if d == null or d.is_elite:
			continue
		if d.behavior == EnemyData.Behavior.SPLITTER and d.split_child_id == "":
			continue      # 分裂子体不算一种怪
		count[d.behavior] = int(count.get(d.behavior, 0)) + 1
	for bh in [EnemyData.Behavior.MELEE, EnemyData.Behavior.RANGED,
		EnemyData.Behavior.CHARGER, EnemyData.Behavior.SPLITTER]:
		_chk(int(count.get(bh, 0)) == 1,
			"行为 %d 只有 1 只基础怪（实得 %d）" % [bh, int(count.get(bh, 0))])

## 全场只用 4 套素材，精英一律复用本体的图。
func _test_art_reuse() -> void:
	var art := {}
	for id in EnemyDB.ids():
		var d: EnemyData = EnemyDB.get_data(id)
		if d == null:
			continue
		art[d.anim_dir if d.anim_dir != "" else d.tex] = true
	_chk(art.size() == 4, "全场只用 4 套素材（实得 %d）：%s" % [art.size(), str(art.keys())])
	for id in EnemyDB.ids():
		var d: EnemyData = EnemyDB.get_data(id)
		if d == null or not d.is_elite:
			continue
		var host: EnemyData = EnemyDB.get_data(d.elite_of)
		_chk(host != null and d.tex == host.tex and d.anim_dir == host.anim_dir,
			"%s 复用本体 %s 的素材" % [id, d.elite_of])

# ── 远程 ────────────────────────────────────────────────────────────
func _setup_ranged() -> void:
	_clear()
	subject = g.spawn_enemy_at("ranged_crystal", g.player.position + Vector2(300, 0))
	subject.spawn_left = 0.0
	subject.cfg.attack_cd = 0.1
	subject.cfg.attack_windup = 0.05
	subject.atk_cd_left = 0.0

func _test_bullet_clear() -> void:
	var n0 := g.enemy_bullets.size()
	_chk(n0 > 0, "清弹前有弹 %d" % n0)
	var hit := g.clear_enemy_bullets_in(g.enemy_bullets[0].pos, 40.0)
	_chk(hit > 0, "范围清弹销毁 %d 发" % hit)
	_chk(g.enemy_bullets.size() == n0 - hit, "被销毁的弹已从弹池移除")
	# 线段清弹（水漫金山那套）
	subject.atk_cd_left = 0.0
	subject._fire_bullet()
	var b = g.enemy_bullets[g.enemy_bullets.size() - 1]
	var seg := g.clear_enemy_bullets_seg(b.pos - b.dir * 20.0, b.dir, 0.0, 60.0, 40.0)
	_chk(seg > 0, "线段清弹销毁 %d 发" % seg)

# ── 冲锋 ────────────────────────────────────────────────────────────
func _setup_charger() -> void:
	_clear()
	subject = g.spawn_enemy_at("charger_fast", g.player.position + Vector2(500, 0))
	subject.spawn_left = 0.0
	subject.cfg.charge_time = 0.3      # 压缩蓄力，测试不空等 2 秒
	subject.cfg.charge_dist = 260.0
	subject.cfg.charge_speed = 700.0
	charge_org = subject.position

# ── 分裂 ────────────────────────────────────────────────────────────
func _test_split() -> void:
	_clear()
	var parent := g.spawn_enemy_at("splitter_bomber", g.player.position + Vector2(360, 0))
	parent.spawn_left = 0.0
	var want := int(EnemyDB.get_data("splitter_bomber").split_count)
	g._kill_enemy(parent)
	var shards := _by_id("splitter_bomber_shard")
	_chk(shards.size() == want, "分裂出 %d 只子体（期望 %d）" % [shards.size(), want])
	if shards.is_empty():
		return
	_chk(shards[0].hp < float(EnemyDB.get_data("splitter_bomber").hp), "子体血量更低")
	_test_split_invuln(shards)
	var before := shards.size()
	g._kill_enemy(shards[0])
	_chk(_by_id("splitter_bomber_shard").size() == before - 1, "子体不会二次分裂")

## 子体出生那 0.5 秒必须免疫伤害，否则会被父体埋在脚下的爆裂连锁当场清掉。
func _test_split_invuln(shards: Array) -> void:
	var kid: Enemy = shards[0]
	_chk(kid.invuln_left > 0.0, "子体带着出生无敌 %.2fs" % kid.invuln_left)
	var hp0 := kid.hp
	g._damage(kid, 999.0, false, "normal")
	_chk(is_equal_approx(kid.hp, hp0) and not kid.dead, "无敌期内免疫伤害")
	kid.try_mark(g.sim_time, 4242, 5.0)
	_chk(not kid.is_marked(g.sim_time), "无敌期内挂不上标记")
	# 父体的爆裂连锁就炸在子体脚下（散开 34px，爆炸半径 90px），必须炸不动
	g._blast_at(kid.position)
	var alive := 0
	for s in shards:
		if is_instance_valid(s) and not s.dead:
			alive += 1
	_chk(alive == shards.size(), "父体爆炸炸不掉无敌中的子体 %d / %d" % [alive, shards.size()])
	# 无敌一过就该正常吃伤害
	for s in shards:
		s.invuln_left = 0.0
	g._damage(kid, 1.0, false, "normal")
	_chk(kid.hp < hp0, "无敌结束后恢复正常受伤 %.1f → %.1f" % [hp0, kid.hp])

# ── 技能命中链路 ────────────────────────────────────────────────────
func _test_skill_hit() -> void:
	_clear()
	var e := g.spawn_enemy_at("elite_melee", g.player.position + Vector2(200, 0))
	e.spawn_left = 0.0
	# 直接伤害
	var hp0 := e.hp
	g._damage(e, 5.0, false, "normal")
	_chk(e.hp < hp0, "_damage 命中新怪 %.1f → %.1f" % [hp0, e.hp])
	# 标记 / 引爆契约
	e.try_mark(g.sim_time, 12345, 7.0)
	_chk(e.is_marked(g.sim_time), "try_mark 挂上标记")
	_chk(is_equal_approx(e.apply_mark(), 7.0), "apply_mark 取回伤害")
	# 雷霆：走 enemies 数组 + cfg.radius 判定
	var hp1 := e.hp
	g._cast_thunder(1.0)
	_chk(e.hp < hp1, "雷霆命中新怪 %.1f → %.1f" % [hp1, e.hp])
	# 击杀链路
	var k0 := g.kills
	g._kill_enemy(e)
	_chk(g.kills == k0 + 1, "击杀计数 +1")
	_chk(not g.enemies.has(e), "击杀后移出 enemies 数组")
	# 冲刺斩顺带清弹
	_clear()
	var r := g.spawn_enemy_at("ranged_crystal", g.player.position + Vector2(300, 0))
	r.spawn_left = 0.0
	r.atk_cd_left = 0.0
	r._fire_bullet()
	var n := g.enemy_bullets.size()
	_chk(n > 0, "开火成功，弹数 %d" % n)
	g._mark_enemies_at(g.enemy_bullets[0].pos, 3.0)
	_chk(g.enemy_bullets.size() < n, "冲刺斩销毁敌弹 %d → %d" % [n, g.enemy_bullets.size()])

# ── 工具 ────────────────────────────────────────────────────────────
func _by_id(id: String) -> Array:
	var out: Array = []
	for e in g.enemies:
		if String(e.cfg.get("id", "")) == id:
			out.append(e)
	return out

func _clear() -> void:
	for e in g.enemies.duplicate():
		e.dead = true
		e.queue_free()
	g.enemies.clear()
	g.enemy_bullets.clear()
	g.blasts.clear()

func _next(p: int) -> void:
	phase = p
	t = 0.0

func _chk(cond: bool, msg: String) -> void:
	if cond:
		print("ok  ", msg)
	else:
		print("BAD ", msg)
		fails.append(msg)
