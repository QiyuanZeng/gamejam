extends Node
## 校验登录页背景已切换为 start.ogv 循环视频。

var fails: Array[String] = []

func _chk(cond: bool, msg: String) -> void:
	if cond:
		print("ok  ", msg)
	else:
		print("BAD ", msg)
		fails.append(msg)

func _ready() -> void:
	var path := "res://assets/start.ogv"
	_chk(ResourceLoader.exists(path), "start.ogv 存在")
	var stream := load(path)
	_chk(stream is VideoStream, "start.ogv 加载为 VideoStream")

	var login: Control = load("res://scenes/login.tscn").instantiate()
	add_child(login)
	await get_tree().process_frame

	var vsp: VideoStreamPlayer = null
	for c in login.get_children():
		if c is VideoStreamPlayer:
			vsp = c
			break
	_chk(vsp != null, "登录页生成 VideoStreamPlayer")
	if vsp != null:
		_chk(vsp.stream != null, "VideoStreamPlayer 已绑定视频流")
		_chk(vsp.loop, "视频循环播放已开启")
		_chk(vsp.expand, "视频铺满节点")
		_chk(vsp.mouse_filter == Control.MOUSE_FILTER_IGNORE, "视频不吃鼠标事件")
		_chk(login.get_child(0) == vsp, "视频位于最底层")

	login.queue_free()
	if fails.is_empty():
		print("VIDEO_BG PASS")
	else:
		for f in fails:
			print("FAIL: ", f)
		print("VIDEO_BG FAIL")
	get_tree().quit(1 if fails.size() > 0 else 0)
