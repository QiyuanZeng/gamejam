class_name Enemy
extends Node2D
## 墨魉(blob 直追) / 疾影(fast 惯性过弯) / 磐妖(tank 厚血慢压) / 爆魈(bomber 死亡连锁爆炸)。
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
var frozen_left := 0.0    # 冰冻咒语
var burn_left := 0.0      # 灼烧刀痕
var burn_dps := 0.0
var seed_v := 0.0
var dead := false
var game
var texture: Texture2D
var sprite: Sprite2D

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

func setup(p_cfg: Dictionary, p_game, p_mat: ShaderMaterial) -> void:
	cfg = p_cfg
	hp = float(cfg.hp)
	_last_hp = hp
	game = p_game
	seed_v = randf() * TAU
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
		add_child(sprite)
	elif texture != null:
		sprite = Sprite2D.new()
		sprite.texture = texture
		var s := float(cfg.tex_target) / float(maxf(texture.get_width(), texture.get_height()))
		sprite.scale = Vector2(s, s)
		if p_mat != null:
			sprite.material = p_mat
		add_child(sprite)
	if game != null and game.player != null:
		var d: Vector2 = game.player.position - position
		if d.length() > 1.0:
			velocity = d.normalized() * float(cfg.speed) * 0.5

func _load_anim(dir: String) -> void:
	for state in ["idle", "move", "attack_thrust", "hit", "death"]:
		var frames: Array[Texture2D] = []
		var i := 0
		while true:
			var p := "%s%s/%s_%02d.png" % [dir, state, state, i]
			if not ResourceLoader.exists(p):
				break
			frames.append(load(p))
			i += 1
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
		if hp < _last_hp:
			hit_flash = 0.22
		_last_hp = hp
		var st := "move" if velocity.length() > 5.0 else "idle"
		if hit_flash > 0.0:
			hit_flash -= delta
			st = "hit"
		_play(st, delta)
	if spawn_left > 0.0:
		spawn_left -= delta
		queue_redraw()
		return
	var factor: float = game.enemy_speed_factor()
	if frozen_left > 0.0:
		factor = 0.0
	if factor > 0.0:
		var to_p: Vector2 = game.player.position - position
		var d := to_p.length()
		if d > 1.0:
			var dir := to_p / d
			if cfg.type == "fast" or cfg.type == "mite":
				# 高速惯性：冲过头再拐回来
				var desired := dir * float(cfg.speed)
				velocity = velocity.lerp(desired, clampf(2.4 * delta, 0.0, 1.0))
				position += velocity * factor * delta
			else:
				velocity = dir * float(cfg.speed)
				position += dir * float(cfg.speed) * factor * delta
	queue_redraw()

func is_marked(now: float) -> bool:
	return (not dead) and pending > 0.0 and now < marked_until

func try_mark(now: float, stamp: int, dmg: float) -> void:
	if dead or spawn_left > 0.0 or mark_stamp == stamp:
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

func _draw() -> void:
	if texture != null or not anims.is_empty() or cfg.is_empty():
		return
	var a := 1.0
	if spawn_left > 0.0:
		a = (1.0 - spawn_left / 0.35) * 0.5
	var base: Color = cfg.color
	var col := Color(base.r, base.g, base.b, a)
	var r: float = float(cfg.radius)
	# 不规则墨团
	var pts := PackedVector2Array()
	var n := 12
	for i in n:
		var ang := TAU * float(i) / float(n) + seed_v
		var rr: float = r * (0.78 + 0.26 * sin(3.0 * ang + seed_v * 2.7))
		pts.append(Vector2(cos(ang), sin(ang)) * rr)
	if cfg.type == "fast":
		# 拉长成疾影
		var dir := velocity.normalized() if velocity.length() > 1.0 else Vector2.RIGHT
		for i in pts.size():
			var p: Vector2 = pts[i]
			var along := p.dot(dir)
			var perp := p - dir * along
			pts[i] = dir * along * 1.55 + perp * 0.55
	draw_colored_polygon(pts, col)
	if cfg.type == "tank":
		draw_circle(Vector2(r * 0.25, r * 0.15), r * 0.28, Color(base.r, base.g, base.b, a * 0.55))
		draw_circle(Vector2(-r * 0.3, -r * 0.2), r * 0.18, Color(base.r, base.g, base.b, a * 0.45))
	if cfg.type == "bomber":
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
