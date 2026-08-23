extends Node
## 落雷特效自检：摆一圈靶子放雷霆万钧，截屏落盘 + 沿电弧逐点比对像素，
## 确认锯齿电弧真的画在屏幕上（不是靠肉眼猜）。必须带渲染跑（不加 --headless）。

var g: Game
var t := 0.0
var life := 0.0
var phase := 0
var fails: Array[String] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	g = Game.new()
	add_child(g)

func _process(delta: float) -> void:
	t += delta
	life += delta
	if life > 30.0:
		print("FAIL: watchdog at phase %d" % phase)
		get_tree().quit(1)
		return
	if g == null:
		return
	g.spawn_timer = 9999.0
	g.player.invuln = 999.0
	match phase:
		0:
			if t > 0.8:
				for i in 5:
					var a := TAU * float(i) / 5.0
					_place(g.player.position + Vector2(cos(a), sin(a)) * 170.0)
				phase = 1
				t = 0.0
		1:
			if t > 0.2:
				phase = 2
				g._cast("thunder")
				_shot()

func _place(pos: Vector2) -> void:
	var e := Enemy.new()
	e.setup(EnemyDB.cfg("melee_mite"), g, null)
	e.position = pos
	e.spawn_left = 0.0
	e.hp = 999.0
	g.add_child(e)
	g.enemies.append(e)

func _shot() -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var dir := ProjectSettings.globalize_path("res://tests/out")
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir + "/thunder_fx.png"
	_chk(img.save_png(path) == OK, "存图 %s" % path)
	_chk(g.bolts.size() > 0, "落下 %d 道雷" % g.bolts.size())

	var vs := Vector2(img.get_size())
	var cam: Vector2 = g.camera.get_screen_center_position()
	var zoom: Vector2 = g.camera.zoom
	var bg := img.get_pixelv(Vector2i(12, int(vs.y) - 12))
	var on := 0
	var total := 0
	for b in g.bolts:
		var main: PackedVector2Array = b.main
		for i in main.size():
			var sp: Vector2 = (main[i] - cam) * zoom + vs * 0.5
			if sp.x < 2.0 or sp.y < 2.0 or sp.x > vs.x - 3.0 or sp.y > vs.y - 3.0:
				continue
			total += 1
			var best := 0.0
			for dy in [-2, -1, 0, 1, 2]:
				for dx in [-2, -1, 0, 1, 2]:
					var px := img.get_pixelv(Vector2i(int(sp.x) + dx, int(sp.y) + dy))
					best = maxf(best, absf(px.r - bg.r) + absf(px.g - bg.g) + absf(px.b - bg.b))
			if best > 0.06:
				on += 1
	var ratio := 0.0 if total == 0 else float(on) / float(total)
	print("bolts=%d onscreen_pts=%d hit=%.2f bg=%s" % [g.bolts.size(), total, ratio, str(bg)])
	_chk(total > 10, "电弧有 %d 个采样点落在画面内" % total)
	_chk(ratio > 0.85, "电弧像素可见率 %.2f" % ratio)
	for f in fails:
		print("FAIL: ", f)
	print("THUNDER_SHOT ", "PASS" if fails.is_empty() else "FAIL")
	get_tree().quit(1 if not fails.is_empty() else 0)

func _chk(cond: bool, msg: String) -> void:
	print(("ok   " if cond else "BAD  "), msg)
	if not cond:
		fails.append(msg)
