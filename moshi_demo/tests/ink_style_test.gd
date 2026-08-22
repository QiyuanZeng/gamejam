extends Node
## 样式系统测试：加载默认值 / 热改 set_param / 保存回读 / 重置 / 编辑器场景实例化与关闭。

var fails: Array[String] = []

func _ready() -> void:
	# res:// 预设值（用户可能在编辑器里调过并存为默认）
	var preset: InkBrushStyle = ResourceLoader.load(
		InkStyle.RES_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	_chk(InkStyle.current != null, "InkStyle.current loaded")
	_chk(absf(InkStyle.current.width_start - preset.width_start) < 0.001,
		"default == res:// preset (%.1f)" % preset.width_start)
	# 热改
	InkStyle.set_param(&"width_start", 25.0)
	_chk(absf(InkStyle.current.width_start - 25.0) < 0.001, "set_param hot")
	InkStyle.set_param(&"ink_color", Color(0, 0, 1, 1))
	_chk(InkStyle.current.ink_color == Color(0, 0, 1, 1), "set_param color")
	# 保存 + 回读
	var e := InkStyle.save_user()
	_chk(e == OK, "save_user err=%d" % e)
	_chk(FileAccess.file_exists(InkStyle.USER_PATH), "user://ink_style.tres exists")
	var s := ResourceLoader.load(InkStyle.USER_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	_chk(s is InkBrushStyle, "saved file is InkBrushStyle")
	if s is InkBrushStyle:
		_chk(absf(s.width_start - 25.0) < 0.001, "persisted width_start=25")
		_chk(s.ink_color == Color(0, 0, 1, 1), "persisted ink_color")
	# 重置
	InkStyle.reset_default()
	_chk(absf(InkStyle.current.width_start - 13.0) < 0.001, "reset_default")
	_chk(InkStyle.current.ink_color == Color("#1A1714"), "reset ink_color")
	# 编辑器场景实例化 + 关闭路径
	var ed = load("res://scenes/ink_editor.tscn").instantiate()
	add_child(ed)
	_chk(ed != null, "editor instantiated")
	await get_tree().process_frame
	await get_tree().process_frame
	ed._on_close()
	_chk(not get_tree().paused, "editor close unpauses tree")
	await get_tree().process_frame
	_chk(not is_instance_valid(ed), "editor freed")
	# 渲染器冒烟：静态函数在无 CanvasItem 情况下不崩
	var tri := Geometry2D.triangulate_polygon(
		InkRenderer.ribbon_poly(
			InkRenderer.smooth_path(
				PackedVector2Array([Vector2(8, 8), Vector2(400, 324), Vector2(650, 324)]), 2),
			[12.0] + range(19).map(func(_i): return 10.0), 1.0, 0.18, 3.7))
	_chk(tri != null and not tri.is_empty(), "renderer ribbon triangulates")
	# 游戏内 F1 集成：开 → 暂停 → 松开武装 → 再按关闭 → 恢复
	var g := Game.new()
	add_child(g)
	g.wave_rest = 999.0
	g._input(_key_ev(KEY_F1, true))
	await get_tree().process_frame
	await get_tree().process_frame
	_chk(g.ink_editor != null, "F1 opens editor in game")
	_chk(get_tree().paused, "tree paused with editor")
	if g.ink_editor != null:
		var ed2: CanvasLayer = g.ink_editor
		ed2._input(_key_ev(KEY_F1, false))  # 松开开启键 → 武装
		ed2._input(_key_ev(KEY_F1, true))   # 再按 → 关闭
		await get_tree().process_frame
		await get_tree().process_frame
		_chk(not get_tree().paused, "editor closed, tree resumed")
		_chk(g.ink_editor == null, "editor ref cleared")
	g.queue_free()
	await get_tree().process_frame
	# 清理测试产生的 user 文件
	DirAccess.remove_absolute(ProjectSettings.globalize_path(InkStyle.USER_PATH))
	InkStyle.reload_from_disk()
	_chk(absf(InkStyle.current.width_start - preset.width_start) < 0.001, "reload falls back to res:// default")
	for f in fails:
		print("FAIL: ", f)
	print("INKSTYLE ", "PASS" if fails.is_empty() else "FAIL")
	get_tree().quit(1 if not fails.is_empty() else 0)

func _key_ev(k: Key, pressed: bool) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = k
	ev.pressed = pressed
	return ev

func _chk(cond: bool, msg: String) -> void:
	print(("ok   " if cond else "BAD  "), msg)
	if not cond:
		fails.append(msg)
