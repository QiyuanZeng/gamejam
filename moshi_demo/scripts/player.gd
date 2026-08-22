class_name Player
extends Node2D
## 无脸兜帽剑客。素材缺失时程序化剪影兜底。
## 脚下时钟（视觉参考 proto/clock-swing 的表盘）：底盘 + 12 刻度 + 长指针（指向移动目标，朱砂针尖）+ 慢转短针。

const RADIUS := 30.0
const INK := Color("#1A1714")
const RED := Color("#C0392B")

## 时钟长指针长度（叠在美术表盘上）
const CLOCK_LONG_HAND := 118.0

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

## 美术时钟表盘（wind_keeper_idle_assets 的 idle_ring，整圆铺脚下，不压扁）
var ring_frames: Array[Texture2D] = []
var ring_idx := 0
var ring_timer := 0.0
const RING_FPS := 6.0
var ring: Sprite2D

func setup(p_mat: ShaderMaterial) -> void:
	for i in 8:
		var frame_path := "res://assets/art/player/idle/idle_%02d.png" % i
		if ResourceLoader.exists(frame_path):
			idle_frames.append(load(frame_path))
	for i in 8:
		var ring_path := "res://assets/art/player/effects/idle_ring/ring_%02d.png" % i
		if ResourceLoader.exists(ring_path):
			ring_frames.append(load(ring_path))
	if ResourceLoader.exists("res://assets/player.png"):
		texture = load("res://assets/player.png")
	if idle_frames.is_empty() and texture == null:
		return
	if not ring_frames.is_empty():
		ring = Sprite2D.new()
		ring.texture = ring_frames[0]
		add_child(ring)
	sprite = Sprite2D.new()
	var tex := idle_frames[0] if not idle_frames.is_empty() else texture
	sprite.texture = tex
	var s := 116.0 / float(maxf(tex.get_width(), tex.get_height()))
	sprite.scale = Vector2(s, s)
	if ring != null:
		# 时钟表盘：整圆、比角色大一圈、垫脚下（先 add_child 已在角色下层）
		var s2 := s * 1.35
		ring.scale = Vector2(s2, s2)
		ring.position = Vector2(0, 3)
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
	if ring != null and not ring_frames.is_empty():
		ring.modulate.a = _alpha
		ring_timer += delta
		if ring_timer >= 1.0 / RING_FPS:
			ring_timer -= 1.0 / RING_FPS
			ring_idx = (ring_idx + 1) % ring_frames.size()
			ring.texture = ring_frames[ring_idx]
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

## 长指针：叠在美术时钟表盘（idle_ring）上——粗黑针身指向移动目标（facing），朱砂针尖（参考 proto/clock-swing）
func _draw_clock() -> void:
	var a := _alpha
	var col := Color(INK.r, INK.g, INK.b, a)
	var red := Color(RED.r, RED.g, RED.b, a)
	var dir := facing.normalized() if facing.length() > 0.01 else Vector2.RIGHT
	draw_line(Vector2.ZERO, dir * CLOCK_LONG_HAND, col, 5.0, true)
	draw_circle(dir * CLOCK_LONG_HAND, 5.0, red)
	draw_circle(Vector2.ZERO, 3.0, red)
