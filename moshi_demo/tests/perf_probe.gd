extends Node
## 帧耗时探针：分阶段测「空场 / 带历史航道 / 冲刺中 / 回溯中」的平均帧时间，
## 定位左键与回溯卡顿的具体来源。必须带渲染跑（不加 --headless），并关掉垂直同步。

var g: Game
var t := 0.0
var life := 0.0
var phase := 0
var samples: Array[float] = []
var report: Array[String] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	g = Game.new()
	add_child(g)

func _process(delta: float) -> void:
	t += delta
	life += delta
	if life > 60.0:
		_dump("watchdog")
		return
	if g != null:
		g.spawn_timer = 9999.0
	match phase:
		0:
			if t > 1.0:
				_begin("A 空场 全开")
		1:
			if _collect(delta, "A 空场 全开"):
				g.bg_layer.visible = false
				_begin("A1 空场 关背景水面")
		2:
			if _collect(delta, "A1 空场 关背景水面"):
				g.hud.visible = false
				_begin("A2 空场 关背景+关HUD")
		3:
			if _collect(delta, "A2 空场 关背景+关HUD"):
				g.fx_layer.visible = false
				_begin("A3 空场 只剩 ink 层")
		4:
			if _collect(delta, "A3 空场 只剩 ink 层"):
				g.bg_layer.visible = true
				g.hud.visible = true
				g.fx_layer.visible = true
				_slash_burst(4)
				phase = 5
				t = 0.0
		5:
			if g.state == g.State.PLAY:
				_begin("B PLAY + 4 段历史航道")
			elif t > 12.0:
				report.append("！斩击没回到 PLAY，state=%d" % g.state)
				_dump("stuck")
		6:
			if _collect(delta, "B PLAY + 4 段历史航道"):
				g.state = g.State.PLAY
				g.ap = 3.0
				g.last_slash = -99.0
				g._dial_slash()
				_begin("C DASH 冲刺中（水痕 + 航道）")
		7:
			if g.state != g.State.DASH:
				# 冲刺太短测不满，补一刀继续
				g.state = g.State.PLAY
				g.ap = 3.0
				g.last_slash = -99.0
				g._dial_slash()
			if _collect(delta, "C DASH 冲刺中（水痕 + 航道）"):
				g.state = g.State.PLAY
				g.clock_charge = g.CLOCK_TIME
				g._begin_rewind()
				_begin("D REWIND 回溯中")
		8:
			if g.state != g.State.REWIND and t > 0.05:
				g.clock_charge = g.CLOCK_TIME
				g.state = g.State.PLAY
				g._begin_rewind()
			if _collect(delta, "D REWIND 回溯中"):
				_dump("done")

func _begin(_label: String) -> void:
	samples.clear()
	t = 0.0
	phase += 1

func _collect(delta: float, label: String) -> bool:
	if t < 0.25:
		return false          # 前 0.25s 热身，不计
	samples.append(delta * 1000.0)
	if samples.size() < 90:
		return false
	var sum := 0.0
	var worst := 0.0
	for s in samples:
		sum += s
		worst = maxf(worst, s)
	var avg := sum / float(samples.size())
	report.append("%-28s avg %6.2f ms (%5.1f fps)  worst %6.2f ms" % [label, avg, 1000.0 / avg, worst])
	return true

func _slash_burst(n: int) -> void:
	for i in n:
		g.state = g.State.PLAY
		g.player.position = Vector2(1200.0 + 120.0 * i, 1200.0 + 90.0 * i)
		g.dial_t = 0.12 * float(i)
		g.ap = 3.0
		g.last_slash = -99.0
		g._dial_slash()
		g.state = g.State.PLAY

func _dump(why: String) -> void:
	print("---- 帧耗时报告（%s）----" % why)
	for r in report:
		print(r)
	var pts := 0
	for p in g.rewind_hist:
		pts += p.size()
	print("hist_segs=%d hist_pts=%d ink_pts=%d dash_pts=%d smooth_iters=%d"
		% [g.rewind_hist.size(), pts, g.ink_path.size(), g.dash_pts.size(),
		WaterRenderer.geti(WaterRenderer.current, "smooth_iters")])
	print("PERF_PROBE PASS")
	get_tree().quit(0)
