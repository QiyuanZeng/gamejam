extends Node
## 人物总表专项：验 data/player.tres 的数值真的灌进了 Game，
## 顺带盯住「墨耗 tv_cost_per_px 调小 → 同一管墨能画更长的线」这条关系。

var fails: Array[String] = []

func _chk(cond: bool, msg: String) -> void:
	print("ok   " if cond else "BAD  ", msg)
	if not cond:
		fails.append(msg)

func _ready() -> void:
	var pc := PlayerConfig.get_config()
	_chk(pc != null, "总表 %s 载得到" % PlayerConfig.PATH)

	var g := Game.new()
	add_child(g)
	await get_tree().process_frame

	# ── 数值确实从总表灌进来了 ──
	_chk(is_equal_approx(g.PLAYER_HP, pc.player_hp), "血量取自总表 %.0f" % g.PLAYER_HP)
	_chk(is_equal_approx(g.player.max_hp, pc.player_hp), "人物身上也是这个血量")
	_chk(is_equal_approx(g.DASH_SPEED, pc.dash_speed), "冲刺速度 %.0f" % g.DASH_SPEED)
	_chk(is_equal_approx(g.DASH_DIST_BASE, pc.dash_dist_base), "冲刺距离 %.0f" % g.DASH_DIST_BASE)
	_chk(is_equal_approx(g.dash_dist(), pc.dash_dist_base), "实际冲刺距离按总表算 %.0f" % g.dash_dist())
	_chk(is_equal_approx(g.DASH_DMG, pc.dash_dmg), "冲刺伤害 %.0f" % g.DASH_DMG)
	_chk(is_equal_approx(g.dash_radius(), pc.dash_radius), "冲刺命中半径 %.0f" % g.dash_radius())
	_chk(is_equal_approx(g.TV_MAX_BASE, pc.tv_max_base), "墨上限 %.0f" % g.TV_MAX_BASE)
	_chk(is_equal_approx(g.tv_max(), pc.tv_max_base), "实际墨上限按总表算 %.0f" % g.tv_max())
	_chk(is_equal_approx(g.TV_COST_PER_PX, pc.tv_cost_per_px), "每像素墨耗 %.2f" % g.TV_COST_PER_PX)
	_chk(g.ap_max() == pc.ap_max_base, "行动点上限 %d" % g.ap_max())
	_chk(is_equal_approx(g.CLOCK_TIME, pc.clock_time), "钟表充能 %.0fs" % g.CLOCK_TIME)
	_chk(is_equal_approx(g.CONTACT_DMG_MULT, pc.contact_dmg_mult),
		"接触伤害倍率 %.2f" % g.CONTACT_DMG_MULT)
	_chk(is_equal_approx(g.HIT_INVULN, pc.hit_invuln), "受击无敌 %.2fs" % g.HIT_INVULN)

	# ── 受伤倍率真的乘上去了 ──
	g.player.invuln = 0.0
	g.CONTACT_DMG_MULT = 0.5
	var hp0: float = g.player.hp
	g.player.take_hit(20.0 * g.CONTACT_DMG_MULT, g.HIT_INVULN)
	_chk(is_equal_approx(g.player.hp, hp0 - 10.0), "倍率 0.5 时 20 点打进来只掉 10")
	_chk(is_equal_approx(g.player.invuln, g.HIT_INVULN), "挨完这下按总表进无敌")
	g.player.hp = hp0
	g.player.invuln = 0.0
	g.CONTACT_DMG_MULT = pc.contact_dmg_mult

	# ── 挨打不掉 R 的充能 ──
	_chk(is_equal_approx(g.HIT_CHARGE_PENALTY, pc.hit_charge_penalty),
		"充能惩罚取自总表 %.1f" % g.HIT_CHARGE_PENALTY)
	g.clock_charge = 8.0
	var mult0: float = g.score_mult
	g._on_player_hurt()
	_chk(is_equal_approx(g.clock_charge, 8.0), "受伤后 R 充能不掉（%.1f）" % g.clock_charge)
	_chk(g.score_mult <= mult0, "分数倍率仍照常受罚")
	g.clock_charge = 0.0
	g.score_mult = mult0
	g.player.hp = g.player.max_hp

	# ── 神纹参数与冷却 ──
	_chk(g.THUNDER_BOLTS == pc.thunder_bolts, "雷霆 %d 道" % g.THUNDER_BOLTS)
	_chk(is_equal_approx(g.QUAKE_RADIUS, pc.quake_radius), "山崩半径 %.0f" % g.QUAKE_RADIUS)
	_chk(g.ENT_COUNT == pc.ent_count, "树人 %d 个" % g.ENT_COUNT)
	_chk(is_equal_approx(g.FLOOD_RANGE, pc.flood_range), "水浪射程 %.0f" % g.FLOOD_RANGE)
	_chk(g.SWORD_INNER + g.SWORD_OUTER == pc.sword_inner + pc.sword_outer,
		"剑阵 %d 把" % (g.SWORD_INNER + g.SWORD_OUTER))
	var cd_ok := true
	for s in g.skills:
		var want: float = pc.skill_cd(String(s.id))
		if want >= 0.0 and not is_equal_approx(float(s.cd), want):
			cd_ok = false
			print("     ·· 冷却对不上：%s 期望 %.1f 实得 %.1f" % [String(s.id), want, float(s.cd)])
	_chk(cd_ok, "五道神纹的冷却全部取自总表")
	# 神纹全放一遍，确认按总表的数量参数出效果
	g._cast("thunder")
	g._cast("ent")
	g._cast("flood")
	g._cast("swords")
	_chk(g.ents.size() == pc.ent_count, "召出 %d 个树人" % g.ents.size())
	_chk(g.floods.size() == pc.flood_dirs, "推出 %d 道水浪" % g.floods.size())
	_chk(g.swords.size() == pc.sword_inner + pc.sword_outer, "落下 %d 把剑" % g.swords.size())

	# ── 墨耗越小画得越长 ──
	# 一管墨能画的长度 = 墨量 / 每像素墨耗，_sample_ink 逐段按这个价钱扣。
	var full := _max_px(g, pc.tv_cost_per_px)
	var half := _max_px(g, pc.tv_cost_per_px * 0.5)
	_chk(half > full * 1.99, "墨耗减半，可画长度翻倍：%.0f → %.0f px" % [full, half])
	_chk(full > 0.0, "当前配置一笔最长能画 %.0f px" % full)

	for f in fails:
		print("FAIL: ", f)
	print("PLAYERCFG ", "PASS" if fails.is_empty() else "FAIL")
	get_tree().quit(1 if not fails.is_empty() else 0)

## 满墨一笔能画多长（px）。墨耗为 0 视作不受限，返回 INF。
func _max_px(g: Game, cost: float) -> float:
	if cost <= 0.0:
		return INF
	return g.tv_max() / cost
