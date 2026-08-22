class_name BleedCanvas
extends Node2D
## 渗墨画布：双 SubViewport 乒乓反馈。
## 每帧：目标画布 = 模糊消褪(另一画布) + 新盖章 → 逐帧迭代 ≈ 扩散方程，痕迹晕开消褪。
## stamp() 盖章（笔形走 WaterRenderer，与局内划线/F1 编辑器同一套水痕）；合成层叠加纸颗粒。
## 扩散/消褪/颗粒参数每帧读 InkStyle.current。

const SIZE := Vector2i(1152, 648)

var _vp: Array[SubViewport] = []
var _stamp_box: Array[Node2D] = []
var _mat_bleed: Array[ShaderMaterial] = []
var _mat_stamp: Array[ShaderMaterial] = []
var _mat_comp: ShaderMaterial
var _composite: TextureRect
var _cur := 0
var _pending: Array = []

func _ready() -> void:
	var sh_bleed: Shader = load("res://shaders/ink_bleed.gdshader")
	var sh_stamp: Shader = load("res://shaders/ink_stamp.gdshader")
	var sh_comp: Shader = load("res://shaders/ink_composite.gdshader")
	for i in 2:
		var vp := SubViewport.new()
		vp.size = SIZE
		vp.transparent_bg = true
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(vp)
		_vp.append(vp)
		# 反馈底：全屏片，读另一画布上一帧
		var rect := ColorRect.new()
		rect.position = Vector2.ZERO
		rect.size = Vector2(SIZE)
		rect.color = Color.WHITE
		var mb := ShaderMaterial.new()
		mb.shader = sh_bleed
		rect.material = mb
		vp.add_child(rect)
		_mat_bleed.append(mb)
		# 盖章容器（在反馈底之上）
		var box := Node2D.new()
		vp.add_child(box)
		_stamp_box.append(box)
		# 盖章材质：读另一画布做减色混色
		var ms := ShaderMaterial.new()
		ms.shader = sh_stamp
		_mat_stamp.append(ms)
	# 互指上一帧纹理
	for i in 2:
		_mat_bleed[i].set_shader_parameter("src_tex", _vp[1 - i].get_texture())
		_mat_stamp[i].set_shader_parameter("prev_tex", _vp[1 - i].get_texture())
	# 合成输出
	_composite = TextureRect.new()
	_composite.position = Vector2.ZERO
	_composite.size = Vector2(SIZE)
	_composite.stretch_mode = TextureRect.STRETCH_SCALE
	_composite.texture = _vp[0].get_texture()
	_mat_comp = ShaderMaterial.new()
	_mat_comp.shader = sh_comp
	_mat_comp.set_shader_parameter("grain_tex", _make_grain())
	_composite.material = _mat_comp
	add_child(_composite)

func stamp(pts: PackedVector2Array, red: bool) -> void:
	if pts.size() < 2:
		return
	_pending.append({"pts": pts.duplicate(), "red": red})

func clear() -> void:
	_pending.clear()
	for i in 2:
		for st in _stamp_box[i].get_children():
			st.free()

func _process(_delta: float) -> void:
	var s: InkBrushStyle = InkStyle.current
	if s == null or s.bleed_enabled < 0.5:
		_pending.clear()
		_composite.visible = false
		for vp in _vp:
			vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	_composite.visible = true
	for vp in _vp:
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# 上一帧的章已画入画布，移除
	for i in 2:
		for st in _stamp_box[i].get_children():
			st.free()
	# 换面：显示刚渲染完的一侧
	_cur = 1 - _cur
	_composite.texture = _vp[_cur].get_texture()
	# 渗墨参数热读
	_mat_bleed[_cur].set_shader_parameter("blur_radius", s.bleed_radius)
	_mat_bleed[_cur].set_shader_parameter("fade", s.bleed_fade)
	_mat_comp.set_shader_parameter("grain_strength", s.grain_strength)
	# 新章盖入当前目标
	for p in _pending:
		var st := PaintLayer.new()
		st.material = _mat_stamp[_cur]
		var pts: PackedVector2Array = p.pts
		var red: bool = p.red
		st.paint = func(c: CanvasItem) -> void:
			WaterRenderer.ensure_loaded()
			var wp := {}
			if red:
				wp = WaterRenderer.current.duplicate(true)
				wp["water_color"] = Color("#C0392B")
				wp["surface_color"] = Color("#C0392B")
			WaterRenderer.draw_water_path(c, pts,
				WaterRenderer.synth_ages(pts.size(), 0.0, 0.0), 1.0, wp)
		_stamp_box[_cur].add_child(st)
	_pending.clear()

func _make_grain() -> ImageTexture:
	var img := Image.create(256, 256, false, Image.FORMAT_L8)
	for y in 256:
		for x in 256:
			var v := 0.75 + randf() * 0.25
			img.set_pixel(x, y, Color(v, v, v))
	return ImageTexture.create_from_image(img)
