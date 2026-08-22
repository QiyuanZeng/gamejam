extends Node
## 渗墨画布结构测试：实例化 / 盖章队列 / 乒乓换面 / 开关降级 / 清空。

var fails: Array[String] = []
var bc: BleedCanvas

func _ready() -> void:
	bc = BleedCanvas.new()
	add_child(bc)
	_chk(bc._vp.size() == 2, "two viewports")
	_chk(bc._composite != null, "composite exists")
	_chk(bc._composite.texture != null, "composite has texture")
	await get_tree().process_frame
	# 盖章
	bc.stamp(PackedVector2Array([Vector2(100, 100), Vector2(300, 300), Vector2(500, 200)]), false)
	_chk(bc._pending.size() == 1, "stamp queued")
	await get_tree().process_frame
	_chk(bc._pending.is_empty(), "pending consumed")
	var cur := bc._cur
	_chk(bc._stamp_box[cur].get_child_count() == 1, "stamp node added to target")
	await get_tree().process_frame
	_chk(bc._stamp_box[0].get_child_count() + bc._stamp_box[1].get_child_count() == 0,
		"stamps cleaned next frame")
	_chk(bc._cur != cur, "ping-pong flipped")
	# 红章
	bc.stamp(PackedVector2Array([Vector2(0, 0), Vector2(50, 50)]), true)
	await get_tree().process_frame
	_chk(bc._pending.is_empty(), "red stamp consumed")
	# 关闭渗墨 → 降级隐藏
	InkStyle.set_param(&"bleed_enabled", 0.0)
	await get_tree().process_frame
	_chk(not bc._composite.visible, "bleed off hides composite")
	_chk(bc._vp[0].render_target_update_mode == SubViewport.UPDATE_DISABLED, "viewports disabled")
	InkStyle.reset_default()
	await get_tree().process_frame
	_chk(bc._composite.visible, "bleed on restores composite")
	# 清空
	bc.stamp(PackedVector2Array([Vector2(0, 0), Vector2(9, 9)]), false)
	bc.clear()
	_chk(bc._pending.is_empty(), "clear empties pending")
	for f in fails:
		print("FAIL: ", f)
	print("BLEED ", "PASS" if fails.is_empty() else "FAIL")
	get_tree().quit(1 if not fails.is_empty() else 0)

func _chk(cond: bool, msg: String) -> void:
	print(("ok   " if cond else "BAD  "), msg)
	if not cond:
		fails.append(msg)
