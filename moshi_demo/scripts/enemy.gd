class_name Enemy
extends Node2D
## 统一怪物类。行为由 cfg.behavior（EnemyData.Behavior 枚举）分发，数值与素材全部来自
## res://data/balance.tres 的 enemies 数组，见 docs/enemies.md。
##
## 红线（技能命中依赖，勿改）：position / hp / dead / spawn_left / cfg.radius / cfg.dmg /
## try_mark / apply_mark / is_marked。
##
## 速度统一乘 game.enemy_speed_factor()：SPELL 子弹时间 0.10 倍，BURST/REWIND 冻结；
## 左键表盘斩的 DASH 为实时（1.0 倍），右键笔画斩的 DASH 冻结。

const RED := Color("#C0392B")

var cfg: Dictionary = {}
var hp := 10.0
var pending := 0.0        # 已标记、待 BURST 结算的伤害
var marked_until := -99.0 # 标记保留截止（时戳）
var mark_stamp := -1      # 本标记所属的冲刺/回溯序号，防同一次反复叠加
var velocity := Vector2.ZERO
var spawn_left := 0.35    # 出生渐显期：不可伤害玩家
var invuln_left := 0.0    # 出生无敌：期间免疫一切伤害与标记（分裂子体用）
var seed_v := 0.0
var dead := false
var game
var texture: Texture2D
var sprite: Sprite2D
var _base_modulate := Color(1, 1, 1, 1)   # 精英 tint 的原值，无敌闪烁结束后要还原

# 帧动画支持（可选）：cfg.anim_dir 指向按状态分目录的成品帧（idle/move/hit/death…）
var anims: Dictionary = {}
var anim_state := "idle"
var anim_idx := 0
var anim_timer := 0.0
var anim_fps := 12.0
var dying := false
var death_left := 0.0
var hit_flash := 0.0
var _last_hp := 0.0

# ── 行为运行时 ──────────────────────────────────────────────────────
var behavior := 0
var attacking := false    # 远程抬手中：播攻击动画
var atk_cd_left := 0.0
var windup_left := 0.0
var charge_state := "chase"   # chase / windup / dash / recover
var charge_t := 0.0
var charge_dir := Vector2.RIGHT
var charge_left := 0.0
var charge_cd_left := 0.0
var boss_phase := 0        # BOSS 血线分段，多阶段扩展位

func setup(p_cfg: Dictionary, p_game, p_mat: ShaderMaterial) -> void:
	cfg = p_cfg
	hp = float(cfg.hp)
	_last_hp = hp
	game = p_game
	behavior = int(cfg.get("behavior", 0))
	seed_v = randf() * TAU
	atk_cd_left = randf_range(0.0, float(cfg.get("attack_cd", 1.6)) * 0.5)
	if String(cfg.get("anim_dir", "")) != "":
		_load_anim(String(cfg.anim_dir))
	if ResourceLoader.exists(String(cfg.tex)):
		texture = load(String(cfg.tex))
	if not anims.is_empty() and anims.has("idle"):
		sprite = Sprite2D.new()
		var tex0: Texture2D = anims["idle"][0]
		sprite.texture = tex0
		var s := float(cfg.tex_target) / float(maxf(tex0.get_width(), tex0.get_height()))
		sprite.scale = Vector2(s, s)
		if cfg.has("pivot_frac"):
			# 美术包固定 pivot（如 crystal_sentinel 的脚底锚点 (0.5, 0.8125)）：锚点对齐节点原点
			var pf: Vector2 = cfg.pivot_frac
			sprite.centered = false
			sprite.offset = Vector2(-pf.x * tex0.get_width(), -pf.y * tex0.get_height())
		add_child(sprite)
	elif texture != null:
		sprite = Sprite2D.new()
		sprite.texture = texture
		var s := float(cfg.tex_target) / float(maxf(texture.get_width(), texture.get_height()))
		sprite.scale = Vector2(s, s)
		if p_mat != null:
			sprite.material = p_mat
		add_child(sprite)
	if sprite != null:
		# 精英改色：同一套素材乘个色调
		_base_modulate = cfg.get("tint", Color(1, 1, 1, 1))
		sprite.modulate = _base_modulate
	if game != null and game.player != null:
		var d: Vector2 = game.player.position - position
		if d.length() > 1.0:
			velocity = d.normalized() * float(cfg.speed) * 0.5

func _load_anim(dir: String) -> void:
	# 目录自动发现：anim_dir 下每个子目录 = 一个动画状态（目录名任意，兼容
	# shadow_mite / crystal_sentinel 等任意美术包命名）；状态目录内所有 .png
	# 按文件名排序即帧序列，不依赖具体命名规则。effects 子目录跳过（特效另行接入）。
	var d := DirAccess.open(dir)
	if d == null:
		return
	d.list_dir_begin()
	var states: Array[String] = []
	var sub_name := d.get_next()
	while sub_name != "":
		if d.current_is_dir() and not sub_name.begins_with(".") and sub_name != "effects":
			states.append(sub_name)
		sub_name = d.get_next()
	d.list_dir_end()
	for state in states:
		var sd := DirAccess.open(dir.path_join(state))
		if sd == null:
			continue
		var files: Array[String] = []
		sd.list_dir_begin()
		var f := sd.get_next()
		while f != "":
			# 导出包里 PNG 登记成 xxx.png.import（.ctex 的侧车），脚本/资源则是 xxx.remap，
			# 两种尾巴都剥掉再按 .png 过滤——enemy_db / wave_db 剥 .remap 同款处理。
			var name := f
			if name.ends_with(".remap"):
				name = name.trim_suffix(".remap")
			elif name.ends_with(".import"):
				name = name.trim_suffix(".import")
			if name.get_extension().to_lower() == "png" and not name.begins_with("."):
				files.append(name)
			f = sd.get_next()
		sd.list_dir_end()
		files.sort()
		var frames: Array[Texture2D] = []
		for fname in files:
			frames.append(load(dir.path_join(state).path_join(fname)))
		if not frames.is_empty():
			anims[state] = frames

func has_death_anim() -> bool:
	return anims.has("death")

func play_death() -> void:
	dying = true
	death_left = float(anims["death"].size()) / anim_fps
	anim_state = ""
	_play("death", 0.0)

func _play(state: String, delta: float, once := false) -> void:
	if not anims.has(state):
		state = "idle"
	if not anims.has(state):
		return
	if state != anim_state:
		anim_state = state
		anim_idx = 0
		anim_timer = 0.0
		_set_frame()
	var frames: Array = anims[state]
	anim_timer += delta
	if anim_timer >= 1.0 / anim_fps:
		anim_timer -= 1.0 / anim_fps
		if once and anim_idx >= frames.size() - 1:
			return
		anim_idx = (anim_idx + 1) % frames.size()
		_set_frame()

func _set_frame() -> void:
	if sprite != null and anims.has(anim_state):
		sprite.texture = anims[anim_state][anim_idx]

func _process(delta: float) -> void:
	if dying:
		_play("death", delta, true)
		death_left -= delta
		if death_left <= 0.0:
			queue_free()
		return
	if dead or game == null or cfg.is_empty():
		return
	if not anims.is_empty():
		_update_anim(delta)
	if invuln_left > 0.0:
		# 无敌期照常流逝：不受子弹时间影响，也不被出生渐显期挡住
		invuln_left -= delta
		_update_invuln_look()
	if spawn_left > 0.0:
		spawn_left -= delta
		queue_redraw()
		return
	var factor: float = game.enemy_speed_factor()
	if factor > 0.0:
		var dt := delta * factor
		match behavior:
			EnemyData.Behavior.RANGED:
				_tick_ranged(dt)
			EnemyData.Behavior.CHARGER:
				_tick_charger(dt)
			EnemyData.Behavior.BOSS:
				_tick_boss(dt)
			_:
				# MELEE / SPLITTER 共用直追
				_tick_melee(dt)
	queue_redraw()

func _update_anim(delta: float) -> void:
	if hp < _last_hp:
		hit_flash = 0.22
	_last_hp = hp
	var st := "move" if velocity.length() > 5.0 else "idle"
	if attacking:
		st = String(cfg.get("anim_attack", "attack"))
	elif charge_state == "windup":
		var cs := String(cfg.get("anim_charge", ""))
		if cs != "":
			st = cs
	if hit_flash > 0.0:
		hit_flash -= delta
		st = "hit"
	if spawn_left > 0.0 and anims.has("spawn"):
		st = "spawn"
	_play(st, delta)

# ── 行为：近战（直追，仅触碰伤害）─────────────────────────────────
func _tick_melee(dt: float) -> void:
	_approach(dt, 0.0)

## 朝玩家推进；stop_at > 0 时进到该距离就停步。返回与玩家的距离。
func _approach(dt: float, stop_at: float) -> float:
	var to_p: Vector2 = game.player.position - position
	var d := to_p.length()
	if d <= 1.0:
		return d
	var dir := to_p / d
	if stop_at > 0.0 and d <= stop_at:
		velocity = velocity.lerp(Vector2.ZERO, clampf(6.0 * dt, 0.0, 1.0))
		return d
	var spd := float(cfg.speed)
	if bool(cfg.get("inertia", false)):
		# 高速惯性：冲过头再拐回来
		velocity = velocity.lerp(dir * spd, clampf(2.4 * dt, 0.0, 1.0))
		position += velocity * dt
	else:
		velocity = dir * spd
		position += dir * spd * dt
	return d

# ── 行为：远程（到攻击距离停步开火）───────────────────────────────
func _tick_ranged(dt: float) -> void:
	var range_at := float(cfg.get("attack_range", 420.0))
	var d := _approach(dt, range_at)
	atk_cd_left = maxf(atk_cd_left - dt, 0.0)
	if d > range_at:
		attacking = false
		windup_left = 0.0
		return
	if attacking:
		windup_left -= dt
		if windup_left <= 0.0:
			attacking = false
			atk_cd_left = float(cfg.get("attack_cd", 1.6))
			_fire_bullet()
	elif atk_cd_left <= 0.0:
		attacking = true
		windup_left = float(cfg.get("attack_windup", 0.35))

func _fire_bullet() -> void:
	if game == null or game.player == null:
		return
	var dir: Vector2 = game.player.position - position
	if dir.length() < 1.0:
		dir = Vector2.RIGHT
	dir = dir.normalized()
	var r: float = float(cfg.radius)
	game.spawn_enemy_bullet(position + dir * r * 0.7, dir, cfg)

# ── 行为：冲锋（停步蓄力 → 直线冲刺）─────────────────────────────
func _tick_charger(dt: float) -> void:
	var range_at := float(cfg.get("charge_range", 600.0))
	match charge_state:
		"chase":
			charge_cd_left = maxf(charge_cd_left - dt, 0.0)
			var d := _approach(dt, 0.0)
			if d <= range_at and charge_cd_left <= 0.0:
				charge_state = "windup"
				charge_t = 0.0
				# 预警红线一出现就把方向钉死：之后玩家怎么跑都不再修正，
				# 红线画的就是最终落点，走位躲得开才算数。
				_lock_charge_dir()
		"windup":
			velocity = velocity.lerp(Vector2.ZERO, clampf(8.0 * dt, 0.0, 1.0))
			charge_t += dt
			if charge_t >= float(cfg.get("charge_time", 2.0)):
				charge_state = "dash"
				charge_left = float(cfg.get("charge_dist", 900.0))
		"dash":
			var step: float = minf(float(cfg.get("charge_speed", 900.0)) * dt, charge_left)
			position += charge_dir * step
			velocity = charge_dir * float(cfg.get("charge_speed", 900.0))
			charge_left -= step
			var lim: Vector2 = game.ARENA - Vector2(8, 8)
			var clamped := position.clamp(Vector2(8, 8), lim)
			if not clamped.is_equal_approx(position):
				position = clamped
				charge_left = 0.0
			if charge_left <= 0.0:
				charge_state = "recover"
				charge_cd_left = float(cfg.get("charge_cd", 2.5))
		_:
			velocity = velocity.lerp(Vector2.ZERO, clampf(5.0 * dt, 0.0, 1.0))
			charge_cd_left -= dt
			if charge_cd_left <= 0.0:
				charge_state = "chase"

## 蓄力起手时锁定冲锋方向。只在进入 windup 的那一帧调一次，
## 之后 charge_dir 不再变——预警红线与实际冲锋路径必须始终是同一条。
func _lock_charge_dir() -> void:
	if game == null or game.player == null:
		return
	var to_p: Vector2 = game.player.position - position
	if to_p.length() > 1.0:
		charge_dir = to_p.normalized()

## 蓄力进度 0~1，预警特效与测试都读它
func charge_progress() -> float:
	if charge_state != "windup":
		return 0.0
	return clampf(charge_t / maxf(float(cfg.get("charge_time", 2.0)), 0.001), 0.0, 1.0)

# ── 行为：BOSS（骨架）──────────────────────────────────────────────
## 现阶段只是小怪技能的组合：远处远程压制，进冲锋范围就蓄力冲撞，冲完接着压制。
## 多阶段扩展位：boss_phase 已按血线算好（0 / 1 / 2），按需在这里换招。
func _tick_boss(dt: float) -> void:
	var ratio := hp / maxf(float(cfg.hp), 0.001)
	boss_phase = 0 if ratio > 0.66 else (1 if ratio > 0.33 else 2)
	if charge_state != "chase":
		_tick_charger(dt)
		return
	charge_cd_left = maxf(charge_cd_left - dt, 0.0)
	_tick_ranged(dt)
	var d: float = game.player.position.distance_to(position)
	if d <= float(cfg.get("charge_range", 700.0)) and charge_cd_left <= 0.0:
		attacking = false
		charge_state = "windup"
		charge_t = 0.0
		_lock_charge_dir()

# ── 无敌期 ──────────────────────────────────────────────────────────
## 无敌期内免疫一切伤害与标记。分裂子体靠它躲过父体炸开的那一下。
func is_invuln() -> bool:
	return invuln_left > 0.0

## 无敌期的可见反馈：快速闪烁，一眼看得出「这只现在打不动」。
func _update_invuln_look() -> void:
	if sprite == null:
		return
	if invuln_left > 0.0:
		var dim := fmod(invuln_left, 0.12) > 0.06
		sprite.modulate = Color(_base_modulate.r, _base_modulate.g, _base_modulate.b,
			_base_modulate.a * (0.35 if dim else 0.8))
	else:
		sprite.modulate = _base_modulate

# ── 标记契约（冲刺斩 / 回溯爆发）──────────────────────────────────
func is_marked(now: float) -> bool:
	return (not dead) and pending > 0.0 and now < marked_until

func try_mark(now: float, stamp: int, dmg: float) -> void:
	if dead or spawn_left > 0.0 or invuln_left > 0.0 or mark_stamp == stamp:
		return
	mark_stamp = stamp
	# 标记尚在保留期内 → 伤害叠加；否则新开一笔
	if now < marked_until:
		pending += dmg
	else:
		pending = dmg
	marked_until = now + float(game.MARK_RETAIN)

func apply_mark() -> float:
	var d := pending
	pending = 0.0
	marked_until = -99.0
	return d

# ── 绘制 ────────────────────────────────────────────────────────────
func _draw() -> void:
	if cfg.is_empty():
		return
	if texture == null and anims.is_empty():
		_draw_body()
	if bool(cfg.get("is_elite", false)):
		_draw_elite_glow()
	_draw_charge_warn()

func _draw_body() -> void:
	var a := 1.0
	if spawn_left > 0.0:
		a = (1.0 - spawn_left / 0.35) * 0.5
	var tint: Color = cfg.get("tint", Color(1, 1, 1, 1))
	var raw: Color = cfg.color
	var base := Color(raw.r * tint.r, raw.g * tint.g, raw.b * tint.b)
	var col := Color(base.r, base.g, base.b, a)
	var r: float = float(cfg.radius)
	var style := String(cfg.get("draw_style", "blob"))
	# 不规则墨团
	var pts := PackedVector2Array()
	var n := 12
	for i in n:
		var ang := TAU * float(i) / float(n) + seed_v
		var rr: float = r * (0.78 + 0.26 * sin(3.0 * ang + seed_v * 2.7))
		pts.append(Vector2(cos(ang), sin(ang)) * rr)
	if style == "fast":
		# 拉长成疾影
		var dir := velocity.normalized() if velocity.length() > 1.0 else Vector2.RIGHT
		for i in pts.size():
			var p: Vector2 = pts[i]
			var along := p.dot(dir)
			var perp := p - dir * along
			pts[i] = dir * along * 1.55 + perp * 0.55
	draw_colored_polygon(pts, col)
	if style == "tank":
		draw_circle(Vector2(r * 0.25, r * 0.15), r * 0.28, Color(base.r, base.g, base.b, a * 0.55))
		draw_circle(Vector2(-r * 0.3, -r * 0.2), r * 0.18, Color(base.r, base.g, base.b, a * 0.45))
	if style == "bomber":
		# 爆魈：朱砂裂纹 + 一点将燃的引芯，视觉预告连锁
		var pulse := 0.5 + 0.5 * sin(seed_v + (game.sim_time if game != null else 0.0) * 7.0)
		draw_arc(Vector2.ZERO, r * 0.72, 0.0, TAU, 18,
			Color(RED.r, RED.g, RED.b, a * (0.3 + 0.4 * pulse)), 2.0)
		draw_line(Vector2(0, -r * 0.8), Vector2(r * 0.25, -r * 1.35),
			Color(RED.r, RED.g, RED.b, a * 0.8), 2.0)
	# 朱砂红点眼（盯着玩家）
	var eye_dir := Vector2.RIGHT
	if game != null and game.player != null:
		var ed: Vector2 = game.player.position - position
		if ed.length() > 1.0:
			eye_dir = ed.normalized()
	draw_circle(eye_dir * r * 0.25, maxf(r * 0.2, 2.5), Color(RED.r, RED.g, RED.b, a))

## 精英光环：三层递减 alpha 的外环 + 呼吸脉动。
## 贴图怪和程序化绘制的怪共用，所以由 _draw() 无条件调用——不能塞回 _draw_body()，
## 那条分支只在「没贴图也没帧动画」时才走，四种怪现在全是贴图怪。
func _draw_elite_glow() -> void:
	var a := 1.0
	if spawn_left > 0.0:
		a = (1.0 - spawn_left / 0.35) * 0.5
	if a <= 0.0:
		return
	var tint: Color = cfg.get("tint", Color(1, 1, 1, 1))
	var t: float = game.sim_time if game != null else 0.0
	var pulse := 0.5 + 0.5 * sin(seed_v + t * 3.2)
	var r: float = float(cfg.radius)
	for i in 3:
		var rr: float = r * (1.06 + 0.13 * float(i)) + r * 0.05 * pulse
		var al: float = a * (0.42 - 0.12 * float(i)) * (0.75 + 0.25 * pulse)
		draw_arc(Vector2.ZERO, rr, 0.0, TAU, 30,
			Color(tint.r, tint.g, tint.b, al), 2.5 - 0.6 * float(i))

## 冲锋预警：一条指向冲锋方向的带子，随蓄力从淡到浓、由短到满地充能。
func _draw_charge_warn() -> void:
	var p := charge_progress()
	if p <= 0.0:
		return
	var warn: Color = cfg.get("charge_warn_color", RED)
	var r: float = float(cfg.radius)
	var full: float = float(cfg.get("charge_dist", 900.0))
	var w: float = r * 0.95
	var perp := Vector2(-charge_dir.y, charge_dir.x)
	# 外框：全长范围，提前告知落点
	var outline := PackedVector2Array([
		-perp * w, charge_dir * full - perp * w,
		charge_dir * full + perp * w, perp * w,
	])
	draw_colored_polygon(outline, Color(warn.r, warn.g, warn.b, 0.07 + 0.05 * p))
	# 充能条：随蓄力向前铺满
	var fl := full * p
	var fill := PackedVector2Array([
		-perp * w, charge_dir * fl - perp * w,
		charge_dir * fl + perp * w, perp * w,
	])
	draw_colored_polygon(fill, Color(warn.r, warn.g, warn.b, 0.16 + 0.26 * p))
	# 蓄力环：临满时闪得最凶
	var pulse := 0.5 + 0.5 * sin(seed_v + (game.sim_time if game != null else 0.0) * (6.0 + 14.0 * p))
	draw_arc(Vector2.ZERO, r * (1.15 + 0.55 * p), 0.0, TAU * p, 30,
		Color(warn.r, warn.g, warn.b, 0.35 + 0.55 * p * pulse), 2.0 + 3.0 * p)
