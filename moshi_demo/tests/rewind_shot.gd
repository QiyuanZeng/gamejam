extends Node
## 回溯航道自检：跑两次表盘斩攒出历史段，充满时钟，截屏落盘 + 逐点比对像素，
## 确认航道线真的画在屏幕上（不是靠肉眼猜）。必须带渲染跑（不加 --headless）。

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
	if g != null:
		g.spawn_timer = 9999.0
	match phase:
		0:
			if t > 0.8:
				_slash(0.0)          # 12 点方向
				phase = 1
				t = 0.0
		1:
			if g.state == g.State.PLAY:
				phase = 2
				t = 0.0
			elif t > 8.0:
				fails.append("dash1 stuck at state %d" % g.state)
				phase = 4
		2:
			if t > 0.2:
				_slash(3.0)          # 3 点方向：拐个弯，航道成链
				phase = 3
				t = 0.0
		3:
			if g.state == g.State.PLAY:
				phase = 4
				t = 0.0
			elif t > 8.0:
				fails.append("dash2 stuck at state %d" % g.state)
				phase = 4
		4:
			if t > 0.3:
				g.clock_charge = g.CLOCK_TIME
				g.camera.zoom = Vector2(0.5, 0.5)   # 拉远，让整条航道进画面
				phase = 5
				_shot()

func _slash(hour: float) -> void:
	g.dial_t = hour
	g.ap = 3.0
	g.last_slash = -99.0
	g._dial_slash()

func _shot() -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var dir := ProjectSettings.globalize_path("res://tests/out")
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir + "/rewind_guide.png"
	var err := img.save_png(path)
	_chk(err == OK, "save png, err=%d" % err)
	_chk(g.rewind_hist.size() >= 2, "hist segs >=2, got %d" % g.rewind_hist.size())
	var vs := Vector2(img.get_size())
	var cam: Vector2 = g.camera.get_screen_center_position()
	var zoom: Vector2 = g.camera.zoom
	# 背景基准色：取路径外的一角
	var bg := img.get_pixelv(Vector2i(12, int(vs.y) - 12))
	var on := 0
	var total := 0
	for seg in g.rewind_hist:
		for i in seg.size():
			var sp: Vector2 = (seg[i] - cam) * zoom + vs * 0.5
			if sp.x < 2.0 or sp.y < 2.0 or sp.x > vs.x - 3.0 or sp.y > vs.y - 3.0:
				continue
			total += 1
			# 线宽有限，取 3x3 邻域里最"不像背景"的一格
			var best := 0.0
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					var px := img.get_pixelv(Vector2i(int(sp.x) + dx, int(sp.y) + dy))
					var d := absf(px.r - bg.r) + absf(px.g - bg.g) + absf(px.b - bg.b)
					best = maxf(best, d)
			if best > 0.06:
				on += 1
	var ratio := 0.0 if total == 0 else float(on) / float(total)
	print("hist=%d onscreen_pts=%d ink_hit=%.2f bg=%s" % [g.rewind_hist.size(), total, ratio, str(bg)])
	print("shot size=%s path=%s" % [str(img.get_size()), path])
	_chk(total > 20, "enough onscreen path points, got %d" % total)
	_chk(ratio > 0.85, "path pixels visible, got %.2f" % ratio)
	if fails.is_empty():
		print("REWIND_SHOT PASS")
		get_tree().quit(0)
	else:
		for f in fails:
			print("FAIL: %s" % f)
		print("REWIND_SHOT FAIL")
		get_tree().quit(1)

func _chk(cond: bool, msg: String) -> void:
	if cond:
		print("ok   %s" % msg)
	else:
		print("BAD  %s" % msg)
		fails.append(msg)
