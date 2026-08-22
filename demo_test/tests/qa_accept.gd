extends Node
## QA 验收探针：TC-P1-07 / TC-P2-01 / TC-P2-02 深度断言（headless 直调内部 API）

var g: Game
var phase := 0
var t := 0.0
var fails: Array[String] = []
var spd_play := 0.0
var spell_start_real := 0
var spell_start_realtime := 0.0
var boom_hp0 := 0.0
var boom_kills0 := 0
var boom_tv0 := 0.0
var boom_mult0 := 0.0
var _mark_pos: Dictionary = {}
var _mark_at := 0
var _spd_pending := false

func _ready() -> void:
	g = Game.new()
	add_child(g)
	g.wave_rest = 999.0  # 隔离自然波次

func _process(delta: float) -> void:
	t += delta
	match phase:
		0:
			if t > 0.5:
				_place(2, "blob", [Vector2(-200, -40), Vector2(-200, 40)])
				phase = 1
				t = 0.0
		1:
			if not _spd_pending and t > 0.4:
				_mark_speed()
				_spd_pending = true
			if _spd_pending:
				var s := _read_speed()
				if s >= 0.0:
					spd_play = s
					_spd_pending = false
					g.time_value = 50.0
					_begin_spell_probe()
					_mark_speed()
					_spd_pending = true
					phase = 2
					t = 0.0
		2:
			if _spd_pending and t > 1.0:
				var spd := _read_speed()
				if spd >= 0.0:
					_spd_pending = false
					_chk(spd < spd_play * 0.55,
						"TC-P1-07: 怪慢速 %.2f < 基线*0.55(%.2f)" % [spd, spd_play * 0.55])
					_chk(spd > spd_play * 0.05,
						"TC-P1-07: 怪未冻住仍在动 %.2f" % spd)
					var wall := (Time.get_ticks_msec() - spell_start_real) / 1000.0
					var rt := g.real_time - spell_start_realtime
					_chk(absf(rt - wall) < 0.5,
						"TC-P1-07: real_time 补偿 %.2f ≈ 墙钟 %.2f" % [rt, wall])
					g._release_spell()
					_chk(absf(Engine.time_scale - 1.0) < 0.001,
						"TC-P1-07: 松开恢复 time_scale 1.0")
					_chk(absf(AudioServer.playback_speed_scale - 1.0) < 0.001,
						"TC-P1-07: 松开恢复音频 1.0")
					_mark_speed()
					_spd_pending = true
					phase = 3
					t = 0.0
		3:
			if _spd_pending and t > 0.5:
				var spd := _read_speed()
				if spd >= 0.0:
					_spd_pending = false
					_chk(spd >= spd_play * 0.8,
						"TC-P1-07: 松开后恢复全速 %.2f >= 基线*0.8(%.2f)" % [spd, spd_play * 0.8])
					phase = 4
					t = 0.0
		4:
			_kill_n(20)
			_chk(absf(g.score_mult - 3.0) < 0.001,
				"TC-P2-01: 20 连杀封顶 mult=%.2f" % g.score_mult)
			_chk(g.score >= 200, "TC-P2-01: score 按倍率累计 %d" % g.score)
			g.player.invuln = 0.0
			var before := g.score_mult
			_force_hit()
			_chk(absf(g.score_mult - before * 0.5) < 0.001,
				"TC-P2-01: 受击减半 %.2f*0.5=%.2f" % [before, g.score_mult])
			_chk(g.combo == 0, "TC-P2-01: 受击清 combo")
			_chk(absf(g.player.hp - g.player.max_hp) < 0.001,
				"TC-P2-01: 受击不扣血 (无死亡机制)")
			for i in 3:
				g.player.invuln = 0.0
				_force_hit()
			_chk(g.score_mult >= 1.0 - 0.001,
				"TC-P2-01: 倍率下限 1.0, got %.2f" % g.score_mult)
			_chk(g.hud != null, "TC-P2-01: HUD 存在 (右上角 ×N.N)")
			phase = 5
			t = 0.0
		5:
			g.score_mult = 1.0
			g.time_value = 10.0
			var b: Enemy = _place(1, "boom", [Vector2(0, 0)])[0]
			_place(4, "blob", [Vector2(0, 40), Vector2(40, 0), Vector2(-40, 0), Vector2(0, -40)])
			_chk(b.cfg.color.to_html(false) == "7a3b2e",
				"TC-P2-02: 爆魉外观红棕 #%s" % b.cfg.color.to_html(false))
			boom_hp0 = g.player.hp
			boom_kills0 = g.kills
			boom_tv0 = g.time_value
			boom_mult0 = g.score_mult
			b.hp = 1.0
			g.kill_list([b])
			_chk(g.boom_queue.size() == 1, "TC-P2-02: 死亡入爆点队列")
			_chk(absf(g.boom_queue[0].t - 0.08) < 0.001,
				"TC-P2-02: 延迟 0.08s 起爆, got %.2f" % g.boom_queue[0].t)
			phase = 6
			t = 0.0
		6:
			if t > 0.25:
				_chk(g.kills > boom_kills0,
					"TC-P2-02: 爆炸连锁击杀 blob (%d -> %d)" % [boom_kills0, g.kills])
				_chk(absf(g.player.hp - boom_hp0) < 0.001, "TC-P2-02: 爆炸不伤玩家")
				_chk(g.time_value > boom_tv0,
					"TC-P2-02: 连锁击杀加 TV (%.1f -> %.1f)" % [boom_tv0, g.time_value])
				_chk(g.score_mult >= boom_mult0, "TC-P2-02: 连锁击杀涨倍率")
				phase = 9
		9:
			for f in fails:
				print("FAIL: ", f)
			print("QA_ACCEPT ", "PASS" if fails.is_empty() else "FAIL")
			get_tree().quit(1 if not fails.is_empty() else 0)

func _begin_spell_probe() -> void:
	g._begin_spell()
	_chk(g.state == g.State.SPELL_DRAW, "TC-P1-07: RMB hold -> SPELL_DRAW")
	_chk(absf(Engine.time_scale - 0.3) < 0.001,
		"TC-P1-07: time_scale 0.3, got %.2f" % Engine.time_scale)
	_chk(absf(AudioServer.playback_speed_scale - 0.3) < 0.001,
		"TC-P1-07: audio playback 0.3 (低沉), got %.2f" % AudioServer.playback_speed_scale)
	spell_start_realtime = g.real_time
	spell_start_real = Time.get_ticks_msec()

func _place(n: int, type_name: String, positions: Array[Vector2]) -> Array[Enemy]:
	var out: Array[Enemy] = []
	for i in n:
		var e := Enemy.new()
		e.setup(g.ENEMY_CFGS[type_name].duplicate(), g, null)
		e.position = positions[i % positions.size()]
		e.spawn_left = 0.0
		g.add_child(e)
		g.enemies.append(e)
		out.append(e)
	return out

func _mark_speed() -> void:
	_mark_pos.clear()
	for i in g.enemies.size():
		if g.enemies[i].dead or g.enemies[i].spawn_left > 0.0:
			continue
		_mark_pos[i] = g.enemies[i].position
	_mark_at = Time.get_ticks_msec()

func _read_speed() -> float:
	var dt := (Time.get_ticks_msec() - _mark_at) / 1000.0
	if dt < 0.2:
		return -1.0  # 采样间隔不足，重试
	var sum := 0.0
	var cnt := 0
	for i in g.enemies.size():
		if not _mark_pos.has(i) or g.enemies[i].dead:
			continue
		sum += g.enemies[i].position.distance_to(_mark_pos[i])
		cnt += 1
	return sum / dt / float(maxi(cnt, 1))

func _kill_n(n: int) -> void:
	for i in n:
		var e := Enemy.new()
		e.setup(g.ENEMY_CFGS["blob"].duplicate(), g, null)
		e.spawn_left = 0.0
		g.add_child(e)
		g.enemies.append(e)
	g.kill_list(g.enemies.duplicate())

func _force_hit() -> void:
	var e := Enemy.new()
	e.setup(g.ENEMY_CFGS["blob"].duplicate(), g, null)
	e.position = g.player.position + Vector2(Player.RADIUS + 5.0, 0)
	e.spawn_left = 0.0
	g.add_child(e)
	g.enemies.append(e)
	g._check_contact()

func _chk(cond: bool, msg: String) -> void:
	print(("ok   " if cond else "BAD  "), msg)
	if not cond:
		fails.append(msg)
