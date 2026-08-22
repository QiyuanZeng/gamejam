class_name Player
extends Node2D
## 无脸兜帽剑客。素材缺失时程序化剪影兜底。
## 平时光标寻径游走（v2 定案手感），按住左键定身画墨，松手沿墨迹冲刺。

const RADIUS := 15.0
const HP_MAX := 140.0
const INK_MAX := 100.0
const INK_REGEN := 16.0
const HOMING_SPEED := 220.0
const STOP_DISTANCE := 30.0
const INVULN_TIME := 1.2
const INK := Color("#1A1714")
const RED := Color("#C0392B")

var hp := HP_MAX
var max_hp := HP_MAX
var ink := INK_MAX
var invuln := 0.0
var facing := Vector2.RIGHT
var bob_t := 0.0
var speed_buff_t := 0.0
var _alpha := 1.0
var texture: Texture2D
var sprite: Sprite2D
var main: Node

func setup(p_mat: ShaderMaterial) -> void:
	if ResourceLoader.exists("res://assets/player.png"):
		texture = load("res://assets/player.png")
	if texture != null:
		sprite = Sprite2D.new()
		sprite.texture = texture
		var s := 58.0 / float(maxf(texture.get_width(), texture.get_height()))
		sprite.scale = Vector2(s, s)
		if p_mat != null:
			sprite.material = p_mat
		add_child(sprite)

func take_hit(dmg: float) -> bool:
	if invuln > 0.0:
		return false
	hp = maxf(hp - dmg, 0.0)
	invuln = INVULN_TIME
	return true

func regen_ink(delta: float) -> void:
	ink = minf(INK_MAX, ink + INK_REGEN * delta)

func update_play(delta: float, target: Vector2) -> void:
	regen_ink(delta)
	if speed_buff_t > 0.0:
		speed_buff_t = maxf(speed_buff_t - delta, 0.0)
	var speed: float = HOMING_SPEED * (1.8 if speed_buff_t > 0.0 else 1.0)
	var to_target := target - position
	var dist := to_target.length()
	if dist > STOP_DISTANCE:
		var step := minf(speed * delta, dist - STOP_DISTANCE)
		position += to_target.normalized() * step
		if step > 0.01:
			facing = to_target.normalized()
	elif dist > 0.01:
		var want := to_target.normalized()
		facing = facing.lerp(want, minf(1.0, delta * 6.0)).normalized()

func _process(delta: float) -> void:
	bob_t += delta
	if invuln > 0.0:
		invuln = maxf(invuln - delta, 0.0)
	_alpha = 1.0
	if invuln > 0.0 and invuln < 90.0:
		_alpha = 0.35 if fmod(bob_t * 24.0, 2.0) < 1.0 else 1.0
	if sprite != null:
		sprite.modulate.a = _alpha
	queue_redraw()

func _draw() -> void:
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
