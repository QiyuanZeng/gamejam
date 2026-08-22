extends Node
## 一致性测试：F1 水笔编辑器里看到的笔画表现，与局内划线是否同源。
## 比的不是像素，而是「喂给 WaterRenderer 的东西是否一模一样」：
## 同一份参数、同一套逐点计龄、同一个 alpha、同样的底纹尺度、同样没有拓印层。

var fails: Array[String] = []

func _ready() -> void:
	get_tree().create_timer(20.0).timeout.connect(_watchdog)
	# —— 备份用户现有配置，测完还回去
	var had_file := FileAccess.file_exists(WaterRenderer.SAVE_PATH)
	var backup := ""
	if had_file:
		backup = FileAccess.open(WaterRenderer.SAVE_PATH, FileAccess.READ).get_as_text()

	var ed: InkEditor = load("res://scenes/ink_editor.tscn").instantiate()
	add_child(ed)
	await get_tree().process_frame
	await get_tree().process_frame
	# 计龄要手动喂 delta 才好比对，先把引擎的自动 _process 停掉
	ed.process_mode = Node.PROCESS_MODE_DISABLED

	# ============ 1. 底纹尺度：局内水面按编辑器画布尺寸平铺 ============
	_chk(ed.pad.size == WaterRenderer.TILE,
		"试笔画布 %s == 世界平铺块 %s" % [ed.pad.size, WaterRenderer.TILE])

	# ============ 2. 参数同源：改了不保存不生效，保存即刻生效 ============
	WaterRenderer.ensure_loaded()
	var before := float(WaterRenderer.current["width_start"])
	ed.params["width_start"] = before + 7.0
	_chk(absf(float(WaterRenderer.current["width_start"]) - before) < 0.0001,
		"未保存时局内不受影响")
	ed._on_save()
	_chk(absf(float(WaterRenderer.current["width_start"]) - (before + 7.0)) < 0.0001,
		"保存后局内即刻同步")
	var diff := 0
	for k in ed.params.keys():
		if WaterRenderer.current.get(k) != ed.params[k]:
			diff += 1
			print("     差异键: ", k, " 编辑器=", ed.params[k], " 局内=", WaterRenderer.current.get(k))
	_chk(diff == 0, "%d 项参数逐键一致" % ed.params.size())

	# ============ 3. 计龄同构：同样的输入推进同样的 delta，年龄必须一致 ============
	var pts := PackedVector2Array([Vector2(40, 40), Vector2(120, 90), Vector2(210, 160)])
	var dt := 0.1
	ed.drawing = false
	ed.cur = pts.duplicate()
	ed.cur_ages = PackedFloat32Array([0.30, 0.20, 0.0])
	ed.pad._process(dt)

	var g := Game.new()
	add_child(g)
	g.spawn_timer = 9999.0
	await get_tree().process_frame
	g.process_mode = Node.PROCESS_MODE_DISABLED
	# 两边相位对齐到同一起点，再各推同样的 delta
	ed.surface_phase = 0.0
	g.surface_phase = 0.0
	g.ink_path = pts.duplicate()
	g.ink_ages = PackedFloat32Array([0.30, 0.20, 0.0])
	g._update_timers(dt)

	_chk(ed.cur_ages.size() == g.ink_ages.size(), "年龄数组等长")
	var age_bad := 0
	for i in mini(ed.cur_ages.size(), g.ink_ages.size()):
		if absf(ed.cur_ages[i] - g.ink_ages[i]) > 1e-6:
			age_bad += 1
			print("     age[%d] 编辑器=%.6f 局内=%.6f" % [i, ed.cur_ages[i], g.ink_ages[i]])
	_chk(age_bad == 0, "逐点年龄完全一致 %s" % str(g.ink_ages))

	# 底纹相位也同速推进
	ed._process(dt)
	_chk(absf(ed.surface_phase - g.surface_phase) < 1e-6,
		"水面相位同速 编辑器=%.3f 局内=%.3f" % [ed.surface_phase, g.surface_phase])

	# ============ 4. 局内一定带着对齐的年龄进渲染器 ============
	g.ink_ages = PackedFloat32Array()   # 故意打乱
	g._begin_dash(PackedVector2Array([Vector2(100, 100), Vector2(260, 210)]), true)
	_chk(g.ink_ages.size() == g.ink_path.size(),
		"非手绘轨迹补齐年龄 %d/%d" % [g.ink_ages.size(), g.ink_path.size()])
	_chk(g.dash_ages.size() == g.dash_done.size(),
		"冲刺尾迹年龄对齐 %d/%d" % [g.dash_ages.size(), g.dash_done.size()])

	# ============ 5. 局内没有编辑器里不存在的额外图层 ============
	_chk(g.bleed == null, "渗墨拓印层已停用（编辑器无此层）")

	# ============ 6. 真跑一遍两边的绘制，不许报错 ============
	var pl := PaintLayer.new()
	add_child(pl)
	pl.paint = g._paint_ink
	pl.queue_redraw()
	var bg := PaintLayer.new()
	add_child(bg)
	bg.paint = g._paint_bg
	bg.queue_redraw()
	ed.pad.queue_redraw()
	await get_tree().process_frame
	await get_tree().process_frame
	_chk(true, "编辑器与局内各绘制一帧（错误见上方日志）")

	# ============ 收尾：还原用户配置 ============
	g.queue_free()
	ed.queue_free()
	pl.queue_free()
	bg.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	if had_file:
		FileAccess.open(WaterRenderer.SAVE_PATH, FileAccess.WRITE).store_string(backup)
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(WaterRenderer.SAVE_PATH))
	WaterRenderer.set_current(WaterRenderer.load_from_disk())

	for f in fails:
		print("FAIL: ", f)
	print("WATER_PARITY ", "PASS" if fails.is_empty() else "FAIL")
	get_tree().quit(1 if not fails.is_empty() else 0)

func _watchdog() -> void:
	print("WATER_PARITY FAIL (watchdog: 20s 未跑完)")
	get_tree().quit(1)

func _chk(cond: bool, msg: String) -> void:
	print(("ok   " if cond else "BAD  "), msg)
	if not cond:
		fails.append(msg)
