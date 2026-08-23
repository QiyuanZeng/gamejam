extends Node
## 结算页截图自检：直接 _settle() 进结算，截屏落盘供肉眼/视觉核对。
## 必须带渲染跑（不加 --headless）。

var g: Game
var t := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	g = Game.new()
	add_child(g)

func _process(delta: float) -> void:
	t += delta
	if g == null:
		return
	g.spawn_timer = 9999.0
	if t > 1.0 and g.state == g.State.PLAY:
		g.score = 5398.0
		g.kills = 12
		g.score_mult = 1.4
		g.payout_sand = 3
		g.run_time = 130.0
		g._settle()
	if g.state == g.State.GAMEOVER and t > 1.6:
		var img := get_viewport().get_texture().get_image()
		img.save_png("res://tests/settle_shot.png")
		print("SHOT SAVED")
		get_tree().quit(0)
	if t > 10.0:
		print("FAIL: watchdog")
		get_tree().quit(1)
