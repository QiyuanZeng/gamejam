class_name Player
extends Node2D
## 无脸兜帽剑客。素材缺失时程序化剪影兜底。
## 脚下时钟（视觉参考 proto/clock-swing 的表盘）：底盘 + 12 刻度 + 长指针（指向移动目标，朱砂针尖）+ 慢转短针。

const RADIUS := 30.0
const INK := Color("#1A1714")
const RED := Color("#C0392B")

## 时钟参数（×2 尺度下）
const CLOCK_R := 52.0
const CLOCK_LONG_HAND := 118.0
const CLOCK_SHORT_R := 26.0

var hp := 100.0
var max_hp := 100.0
var invuln := 0.0
var facing := Vector2.RIGHT
var bob_t := 0.0
var _alpha := 1.0
var texture: Texture2D
var sprite: Sprite2D

var idle_frames: Array[Texture2D] = []
var idle_frame_idx := 0
var idle_timer := 0.0
const IDLE_FPS := 12.0

func setup(p_mat: ShaderMaterial) -> void:
	for i in 8:
		var frame_path := "res://assets/art/player/idle/idle_%02d.png" % i
		if ResourceLoader.exists(frame_path):
			idle_frames.append(load(frame_path))
	if ResourceLoader.exists("res://assets/player.png"):
		texture = load("res://assets/player.png")
	if idle_frames.is_empty() and texture == null:
		return
	sprite = Sprite2D.new()
	var tex := idle_frames[0] if not idle_frames.is_empty() else texture
	sprite.texture = tex
	var s := 116.0 / float(maxf(tex.get_width(), tex.get_height()))
	sprite.scale = Vector2(s, s)
	if idle_frames.is_empty() and p_mat != null:
		sprite.material = p_mat
	add_child(sprite)

func take_hit(dmg: float) -> bool:
	if invuln > 0.0:
		return false
	hp = maxf(hp - dmg, 0.0)
	invuln = 0.6
	return true

func _process(delta: float) -> void:
	bob_t += delta
	if invuln > 0.0:
		invuln = maxf(invuln - delta, 0.0)
	_alpha = 1.0
	if invuln > 0.0 and invuln < 90.0:
		_alpha = 0.35 if fmod(bob_t * 24.0, 2.0) < 1.0 else 1.0
	if sprite != null:
		sprite.modulate.a = _alpha
		if not idle_frames.is_empty():
			idle_timer += delta
			if idle_timer >= 1.0 / IDLE_FPS:
				idle_timer -= 1.0 / IDLE_FPS
				idle_frame_idx = (idle_frame_idx + 1) % idle_frames.size()
				sprite.texture = idle_frames[idle_frame_idx]
	queue_redraw()

func _draw() -> void:
	_draw_clock()
	if texture != null:
		return
	var col := Color(INK.r, INK.g, INK.b, _alpha)
	var red := Color(RED.r, RED.g, RED.b, _alpha)
	var bob := sin(bob_t * 3.0) * 2.0
	# 斗篷
	var pts := PackedVector2Array([
		Vector2(-12, 14), Vector2(0, -16 + bob), Vector2(12, 14), Vector2(0, 8),
	])
	draw_colored_polygon(pts, col)
	# 兜帽头
	draw_circle(Vector2(0, -14 + bob), 7.0, col)
	# 朱砂腰点
	draw_circle(Vector2(0, 6 + bob), 2.5, red)
	# 笔形刀（朝 facing）
	var dir := facing.normalized() if facing.length() > 0.01 else Vector2.RIGHT
	draw_line(dir * 8.0, dir * 26.0, col, 3.0)

## 脚下时钟（参考 proto/clock-swing _paint_clock 的视觉语言）：
## 墨色底盘 + 12 点加粗刻度 + 长指针（指向 facing，朱砂针尖）+ 慢转短针 + 外圈提示弧
func _draw_clock() -> void:
	var a := _alpha
	var col := Color(INK.r, INK.g, INK.b, a)
	var red := Color(RED.r, RED.g, RED.b, a)
	var grey := Color("#4A443C", a)
	# 底盘
	draw_circle(Vector2.ZERO, CLOCK_R, Color(0.0, 0.0, 0.0, 0.10 * a))
	draw_arc(Vector2.ZERO, CLOCK_R, 0.0, TAU, 48, col, 2.5, true)
	# 12 刻度：12 点方向加粗（"总是从这里开始"）
	draw_line(Vector2(0, -CLOCK_R), Vector2(0, -CLOCK_R + 9.0), col, 3.5, true)
	for i in 12:
		if i == 0:
			continue
		var ang := TAU * i / 12.0 - PI * 0.5
		var d := Vector2(cos(ang), sin(ang))
		var w := 2.0 if i % 3 == 0 else 1.2
		draw_line(d * (CLOCK_R - 6.0), d * (CLOCK_R - 2.0), grey, w, true)
	# 长指针：粗黑针身 + 朱砂针尖，指向移动目标（facing）
	var dir := facing.normalized() if facing.length() > 0.01 else Vector2.RIGHT
	draw_line(Vector2.ZERO, dir * CLOCK_LONG_HAND, col, 5.0, true)
	draw_circle(dir * CLOCK_LONG_HAND, 5.0, red)
	draw_circle(Vector2.ZERO, 3.0, red)
	# 慢转短针（装饰，8 秒一圈）
	var short_ang := TAU * fmod(bob_t / 8.0, 1.0) - PI * 0.5
	var sdir := Vector2(cos(short_ang), sin(short_ang))
	draw_line(Vector2.ZERO, sdir * CLOCK_SHORT_R, grey, 3.0, true)
	# 顺时针方向提示弧（外圈小弧 + 箭头感）
	var arc_a0 := dir.angle() + 0.35
	draw_arc(Vector2.ZERO, CLOCK_R + 7.0, arc_a0, arc_a0 + 0.5, 12, grey, 1.5, true)
