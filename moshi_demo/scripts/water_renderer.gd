class_name WaterRenderer
extends RefCounted
## 水体尾迹渲染器（静态，纯函数）—— 飞鸟浮空掠过水面的流体痕迹。
## 局内划线、地面拓印、F1 编辑器共用同一套参数（current，来自 user://water_style.json）。
##
## 动态：每个采样点带独立年龄（秒）。年龄推进 → 切痕淡出、V 形散波向外扩张、
## 涟漪环扩大变淡、泡沫消散。尾部（最早落点）先消失，形成掠过后逐渐愈合的水面。
## 参数以 Dictionary 传入；传空字典则用 current，键缺失时回退 DEFAULTS。
##
## DEFAULTS 就是**出厂水面**：user://water_style.json 不存在时用它，F1 编辑器的
## 「恢复默认」也回到它。改这里等于换全局默认水面。

const DEFAULTS := {
	# —— 接触切痕（掠水瞬时亮痕，柔和不锐利）
	"cut_width": 10.0,
	"cut_alpha": 0.82,
	"cut_life": 1.0,
	# —— 水体尾迹带
	"width_start": 40.0,
	"width_end": 8.7,
	"width_taper": 0.2,
	"head_soft": 0.24,
	"spread_speed": 23.0,
	"body_alpha": 0.42,
	"halo_scale": 1.25,
	"halo_alpha": 0.0,
	"edge_jitter": 0.32,
	"wobble_amp": 2.65,
	"wobble_freq": 48.0,
	"smooth_iters": 3,
	# —— 脚印（分段落点，踩水的离散印记）
	"print_step": 11,
	"print_size": 7.5,
	"print_stagger": 14.5,
	"print_alpha": 0.6,
	"print_squash": 0.29,
	"print_life": 1.8,
	"print_ring": 0.55,
	# —— V 形散波（开尔文尾波，掠水标志）
	"wake_angle": 1.2,
	"wake_speed": 0.0,
	"wake_alpha": 0.4,
	"wake_crest": 5.3,
	"wake_arms": 2,
	# —— 焦散高光
	"caustic_chance": 0.98,
	"caustic_alpha": 0.6,
	"caustic_len_max": 16.0,
	# —— 泡沫
	"foam_step": 2,
	"foam_chance": 0.92,
	"foam_alpha": 1.0,
	"foam_size_max": 1.4,
	"foam_spread": 19.0,
	# —— 扩散涟漪环
	"ripple_step": 11,
	"ripple_radius": 15.0,
	"ripple_speed": 0.0,
	"ripple_alpha": 1.0,
	# —— 生命周期
	"life_time": 8.7,
	"fade_curve": 2.75,
	# —— 配色（青蓝水面）
	"water_color": Color("#5F9BE1"),
	"foam_color": Color("#FFF4C8"),
	"surface_color": Color("#6AD6EB"),
}

const SAVE_PATH := "user://water_style.json"

## 全局生效的一份参数：编辑器「保存并应用」写入，局内绘制读取。
static var current: Dictionary = {}

static func ensure_loaded() -> void:
	if current.is_empty():
		current = load_from_disk()

static func load_from_disk() -> Dictionary:
	var p := DEFAULTS.duplicate(true)
	if not FileAccess.file_exists(SAVE_PATH):
		return p
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return p
	var data: Variant = JSON.parse_string(f.get_as_text())
	if data is Dictionary:
		for k in p.keys():
			if not data.has(k):
				continue
			if p[k] is Color:
				p[k] = Color(str(data[k]))
			else:
				p[k] = data[k]
	return p

static func set_current(p: Dictionary) -> void:
	current = p.duplicate(true)

static func save_to_disk(p: Dictionary) -> Error:
	var out := {}
	for k in p.keys():
		out[k] = ("#" + (p[k] as Color).to_html(false)) if p[k] is Color else p[k]
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(out, "\t"))
	return OK

## 沿路径合成年龄：起笔点最老、笔尖最新。base 为笔尖已存在的秒数。
static func synth_ages(n: int, base: float, span: float) -> PackedFloat32Array:
	var a := PackedFloat32Array()
	for i in n:
		var t := 1.0 if n <= 1 else float(i) / float(n - 1)
		a.append(base + span * (1.0 - t))
	return a

static func get_p(p: Dictionary, key: String) -> Variant:
	return p[key] if p.has(key) else DEFAULTS[key]

static func getf(p: Dictionary, key: String) -> float:
	return float(get_p(p, key))

static func geti(p: Dictionary, key: String) -> int:
	return int(get_p(p, key))

static func getc(p: Dictionary, key: String) -> Color:
	return get_p(p, key) as Color

static func hash_f(i: int) -> float:
	return fposmod(sin(float(i) * 12.9898) * 43758.5453, 1.0)

static func tangent(pts: PackedVector2Array, i: int) -> Vector2:
	var m := pts.size()
	var a: Vector2 = pts[maxi(0, i - 1)]
	var b: Vector2 = pts[mini(m - 1, i + 1)]
	var d := b - a
	return d.normalized() if d.length() > 0.0001 else Vector2.RIGHT

## 平滑路径，同时把年龄数组按归一化位置重采样到新点数
static func smooth_with_ages(pts: PackedVector2Array, ages: PackedFloat32Array, iters: int) -> Array:
	var cur := pts
	for _k in iters:
		var m := cur.size()
		if m < 3:
			break
		var nxt := PackedVector2Array()
		nxt.append(cur[0])
		for i in m - 1:
			var a: Vector2 = cur[i]
			var b: Vector2 = cur[i + 1]
			nxt.append(a.lerp(b, 0.25))
			nxt.append(a.lerp(b, 0.75))
		nxt.append(cur[m - 1])
		cur = nxt
	var n := cur.size()
	var out_ages := PackedFloat32Array()
	var src := ages.size()
	for i in n:
		if src == 0:
			out_ages.append(0.0)
			continue
		var t := 0.0 if n <= 1 else float(i) / float(n - 1)
		var fi := t * float(src - 1)
		var i0 := int(floorf(fi))
		var i1 := mini(i0 + 1, src - 1)
		out_ages.append(lerpf(ages[i0], ages[i1], fi - float(i0)))
	return [cur, out_ages]

## 年龄 → 存活度（1 新鲜 → 0 消失）
static func life_of(age: float, life_time: float, curve: float) -> float:
	if life_time <= 0.0:
		return 0.0
	return pow(clampf(1.0 - age / life_time, 0.0, 1.0), curve)

## 带顶点色的缎带。整条一次性提交成三角数组 —— 兼容渲染器下每个 draw_* 都是独立
## canvas item（实测 ~25µs/次），逐段 draw_polygon 会把一条尾迹拆成上千次调用。
static func ribbon_gradient(c: CanvasItem, pts: PackedVector2Array, widths: Array,
		cols: Array, scale: float, jitter: float, seed: float) -> void:
	var m := pts.size()
	if m < 2:
		return
	var verts := PackedVector2Array()
	var vcols := PackedColorArray()
	verts.resize(m * 2)
	vcols.resize(m * 2)
	for i in m:
		var dir := tangent(pts, i)
		var nrm := Vector2(-dir.y, dir.x)
		var w: float = float(widths[i]) * scale
		var h := sin(float(i) * 0.41 + seed * 3.1) * 0.55 + sin(float(i) * 0.13 + seed) * 0.45
		var j := h * w * jitter
		var col: Color = cols[i]
		verts[i * 2] = pts[i] + nrm * (w + j)
		verts[i * 2 + 1] = pts[i] - nrm * (w - j)
		vcols[i * 2] = col
		vcols[i * 2 + 1] = col
	var idx := PackedInt32Array()
	for i in m - 1:
		var c0: Color = cols[i]
		var c1: Color = cols[i + 1]
		if c0.a <= 0.003 and c1.a <= 0.003:
			continue
		# 锥化尖端的宽度是亚像素级：画出来看不见，白占顶点
		if maxf(float(widths[i]), float(widths[i + 1])) * scale < 0.25:
			continue
		var b := i * 2
		idx.append_array(PackedInt32Array([b, b + 2, b + 3, b, b + 3, b + 1]))
	if idx.is_empty():
		return
	RenderingServer.canvas_item_add_triangle_array(c.get_canvas_item(), idx, verts, vcols)

## 批量画圆：几百个泡沫点逐个 draw_circle 同样会把帧时打穿，合成一次三角数组提交。
static func batch_circles(c: CanvasItem, centers: PackedVector2Array,
		radii: PackedFloat32Array, cols: PackedColorArray, seg := 8) -> void:
	if centers.is_empty():
		return
	var verts := PackedVector2Array()
	var vc := PackedColorArray()
	var idx := PackedInt32Array()
	for k in centers.size():
		var base := verts.size()
		verts.append(centers[k])
		vc.append(cols[k])
		for s in seg:
			var a := TAU * float(s) / float(seg)
			verts.append(centers[k] + Vector2(cos(a), sin(a)) * radii[k])
			vc.append(cols[k])
		for s in seg:
			idx.append(base)
			idx.append(base + 1 + s)
			idx.append(base + 1 + (s + 1) % seg)
	RenderingServer.canvas_item_add_triangle_array(c.get_canvas_item(), idx, verts, vc)

## 单个三角形（零面积 / 过扁 / 非法坐标直接丢弃）
static func tri(c: CanvasItem, a: Vector2, b: Vector2, d: Vector2,
		ca: Color, cb: Color, cd: Color) -> void:
	if not (is_finite(a.x) and is_finite(a.y) and is_finite(b.x) and is_finite(b.y) \
		and is_finite(d.x) and is_finite(d.y)):
		return
	# 绝对面积阈值拦不住"长而扁"的针状三角（路径 180° 折返时成片出现），
	# 它们画出来看不见却会让引擎三角化失败刷屏 —— 按最小高判：低于半像素直接丢。
	var ab := b - a
	var ad := d - a
	var longest := maxf(ab.length(), maxf(ad.length(), (d - b).length()))
	if longest < 0.05:
		return
	if absf(ab.cross(ad)) < 0.5 * longest:
		return
	c.draw_polygon(PackedVector2Array([a, b, d]), PackedColorArray([ca, cb, cd]))

## 水面底纹：浅蓝白底 + 焦散网（程序化、确定性；phase 可让底纹缓慢流动）
## seed_off 让平铺时相邻块图案不重样。
static func draw_water_surface(c: CanvasItem, rect: Rect2, p: Dictionary, phase := 0.0,
		seed_off := 0) -> void:
	if p.is_empty():
		ensure_loaded()
		p = current
	var surf := getc(p, "surface_color")
	var water := getc(p, "water_color")
	var foam := getc(p, "foam_color")
	c.draw_rect(rect, surf)
	for k0 in 26:
		var k := k0 + seed_off
		var hx := hash_f(k * 5 + 3)
		var hy := hash_f(k * 7 + 11)
		var hr := hash_f(k * 11 + 23)
		var drift := sin(phase * 0.25 + hx * 6.28) * rect.size.x * 0.012
		var ctr := rect.position + Vector2(hx * rect.size.x + drift, hy * rect.size.y)
		var r := lerpf(rect.size.y * 0.06, rect.size.y * 0.22, hr)
		c.draw_circle(ctr, r, Color(water.r, water.g, water.b, 0.06 + hr * 0.05))
	for k0 in 46:
		var k := k0 + seed_off
		var h0 := hash_f(k * 13 + 5)
		var h1 := hash_f(k * 17 + 29)
		var y0 := rect.position.y + h0 * rect.size.y
		var amp := lerpf(6.0, 22.0, h1)
		var freq := lerpf(0.010, 0.028, hash_f(k * 3 + 41))
		var line := PackedVector2Array()
		var steps := 30
		for i in steps + 1:
			var t := float(i) / float(steps)
			var x := rect.position.x + t * rect.size.x
			var y := y0 + sin(t * rect.size.x * freq + h0 * 9.0 + phase * 0.6) * amp \
				+ sin(t * rect.size.x * freq * 2.7 + h1 * 5.0 + phase * 0.9) * amp * 0.4
			line.append(Vector2(x, clampf(y, rect.position.y, rect.end.y)))
		c.draw_polyline(line, Color(foam.r, foam.g, foam.b, 0.09 + h1 * 0.11), 1.0 + h0 * 1.2)

## 编辑器试笔画布尺寸。世界里按这个尺寸平铺水面，底纹特征大小才和 F1 里看到的一模一样。
const TILE := Vector2(744.0, 590.0)

## 平铺水面：只画与 view 相交的块，避免整张竞技场每帧几千次 draw。
static func draw_water_surface_tiled(c: CanvasItem, world: Rect2, view: Rect2,
		p: Dictionary, phase := 0.0) -> void:
	if p.is_empty():
		ensure_loaded()
		p = current
	c.draw_rect(world, getc(p, "surface_color"))
	var clip := world.intersection(view)
	if clip.size.x <= 0.0 or clip.size.y <= 0.0:
		return
	var i0 := int(floorf((clip.position.x - world.position.x) / TILE.x))
	var i1 := int(floorf((clip.end.x - world.position.x) / TILE.x))
	var j0 := int(floorf((clip.position.y - world.position.y) / TILE.y))
	var j1 := int(floorf((clip.end.y - world.position.y) / TILE.y))
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			var org := world.position + Vector2(float(i) * TILE.x, float(j) * TILE.y)
			draw_water_surface(c, Rect2(org, TILE), p, phase, (i * 7 + j * 13) * 31)

## 单条尾迹的点数上限。缎带是逐段两个 draw_polygon，点数直接等于每帧 draw 调用数，
## 不设顶的话一条 400 点的路径经 3 次 Chaikin 会炸到 3000+ 点。
const MAX_INPUT_PTS := 200
const MAX_SMOOTH_PTS := 400

## 等距抽稀，首尾必留；ages 同步取样。
static func decimate(pts: PackedVector2Array, ages: PackedFloat32Array,
		limit: int) -> Array:
	var n := pts.size()
	if n <= limit:
		return [pts, ages]
	var out := PackedVector2Array()
	var out_a := PackedFloat32Array()
	var has_ages := ages.size() == n
	for k in limit:
		var i := int(round(float(k) * float(n - 1) / float(limit - 1)))
		out.append(pts[i])
		out_a.append(ages[i] if has_ages else 0.0)
	return [out, out_a]

## 主入口：飞鸟掠水尾迹。ages[i] 为对应采样点已存在的秒数（尾部最大）。
static func draw_water_path(c: CanvasItem, pts: PackedVector2Array,
		ages: PackedFloat32Array, alpha: float, p: Dictionary = {}) -> void:
	if pts.size() < 2:
		return
	if p.is_empty():
		ensure_loaded()
		p = current
	var cut := decimate(pts, ages, MAX_INPUT_PTS)
	var in_pts: PackedVector2Array = cut[0]
	var in_ages: PackedFloat32Array = cut[1]
	# 平滑迭代按点数自适应降级：Chaikin 每轮翻倍，密路径本来就够顺，不需要再翻
	var iters := maxi(geti(p, "smooth_iters"), 0)
	while iters > 0 and in_pts.size() * (1 << iters) > MAX_SMOOTH_PTS:
		iters -= 1
	var res := smooth_with_ages(in_pts, in_ages, iters)
	var sp: PackedVector2Array = res[0]
	var sa: PackedFloat32Array = res[1]
	var m := sp.size()
	if m < 2:
		return
	var seed := float(int(in_pts[0].x) % 977) * 0.37 + float(int(in_pts[0].y) % 761) * 0.11
	var water := getc(p, "water_color")
	var foam := getc(p, "foam_color")
	var life_time := getf(p, "life_time")
	var curve := getf(p, "fade_curve")
	var w_start := getf(p, "width_start") * 0.1
	var w_end := getf(p, "width_end") * 0.1
	var w_taper := getf(p, "width_taper")
	var spread := getf(p, "spread_speed")
	var wob_amp := getf(p, "wobble_amp")
	var wob_freq := getf(p, "wobble_freq")

	# 逐点存活度 + 随年龄扩张的宽度（老的部分摊得更宽更淡 → 掠过后的散开尾波）
	# 头尾各做锥化：起点从 0 渐开、终点渐收，消除平口硬边
	var head_soft := clampf(getf(p, "head_soft"), 0.001, 0.9)
	var lives: Array = []
	var widths: Array = []
	for i in m:
		var lf := life_of(sa[i], life_time, curve)
		lives.append(lf)
		var t := 0.0 if m <= 1 else float(i) / float(m - 1)
		var wbase := lerpf(w_start, w_end, pow(t, w_taper))
		var wob := sin(t * wob_freq + seed) * 0.9 \
			+ (hash_f(i * 3 + int(seed * 10.0)) * 2.0 - 1.0) * wob_amp
		var w := maxf(wbase + spread * sa[i] * 0.35 + wob, 0.6)
		# 起点锥化（smoothstep 渐开）
		var ht := clampf(t / head_soft, 0.0, 1.0)
		var taper_h := ht * ht * (3.0 - 2.0 * ht)
		# 终点锥化
		var tt := clampf((1.0 - t) / head_soft, 0.0, 1.0)
		var taper_t := tt * tt * (3.0 - 2.0 * tt)
		widths.append(maxf(w * taper_h * taper_t, 0.05))

	# 1) 外圈浅水扰动
	var halo_a := alpha * getf(p, "halo_alpha")
	var cols_halo: Array = []
	for i in m:
		cols_halo.append(Color(water.r, water.g, water.b, halo_a * float(lives[i])))
	ribbon_gradient(c, sp, widths, cols_halo,
		getf(p, "halo_scale"), getf(p, "edge_jitter") * 1.4, seed)
	# 2) 水体主带
	var body_a := alpha * getf(p, "body_alpha")
	var cols_body: Array = []
	for i in m:
		cols_body.append(Color(water.r, water.g, water.b, body_a * float(lives[i])))
	ribbon_gradient(c, sp, widths, cols_body, 1.0, getf(p, "edge_jitter"), seed)
	# 2b) 端点圆头：用几层递减圆填补锥尖，彻底消除方口
	for ei in [0, m - 1]:
		var lf_e: float = float(lives[ei])
		if lf_e <= 0.01:
			continue
		var t_e := 0.0 if m <= 1 else float(ei) / float(m - 1)
		var wr := lerpf(w_start, w_end, pow(t_e, w_taper)) + spread * sa[ei] * 0.35
		var dir_e := tangent(sp, ei)
		var inward := dir_e if ei == 0 else -dir_e
		for k in 4:
			var f := float(k) / 4.0
			var pos := sp[ei] + inward * (wr * f * 1.1)
			var rr := wr * (0.25 + 0.75 * f)
			var a := body_a * lf_e * (0.30 + 0.55 * f)
			c.draw_circle(pos, rr, Color(water.r, water.g, water.b, a))

	# 3) V 形散波：从每点向两侧按角度斜后方推进，偏移随年龄增长 → 张成 V
	var wk_ang := getf(p, "wake_angle")
	var wk_spd := getf(p, "wake_speed")
	var wk_a := alpha * getf(p, "wake_alpha")
	var wk_w := getf(p, "wake_crest")
	var arms := maxi(geti(p, "wake_arms"), 0)
	for a_i in arms:
		var arm_scale := 1.0 - float(a_i) * 0.42
		for side_v in [-1.0, 1.0]:
			var side := float(side_v)
			var crest := PackedVector2Array()
			var crest_cols := PackedColorArray()
			for i in m:
				var lf: float = float(lives[i])
				if lf <= 0.004:
					continue
				var dir := tangent(sp, i)
				var nrm: Vector2 = Vector2(-dir.y, dir.x) * side
				# 斜后方向：法向偏转 wake_angle，随年龄外推
				var out_dir: Vector2 = nrm.rotated(-side * wk_ang)
				var dist := (float(widths[i]) * 0.6 + wk_spd * sa[i]) * arm_scale
				var jit := (hash_f(i * 23 + a_i * 71 + int(seed * 9.0)) * 2.0 - 1.0) * 2.6
				var tw_i := float(i) / float(m - 1)
				var fade_end := smoothstep(0.0, head_soft, tw_i) \
					* smoothstep(0.0, head_soft * 0.6, 1.0 - tw_i)
				crest.append(sp[i] + out_dir * dist + dir * jit)
				crest_cols.append(Color(foam.r, foam.g, foam.b,
					wk_a * lf * arm_scale * (0.45 + 0.55 * lf) * fade_end))
			if crest.size() >= 2:
				c.draw_polyline_colors(crest, crest_cols, wk_w * arm_scale)

	# 4) 扩散涟漪环：从落点向外扩大、变淡
	var rp_step := maxi(geti(p, "ripple_step"), 1)
	var rp_r := getf(p, "ripple_radius")
	var rp_spd := getf(p, "ripple_speed")
	var rp_a := alpha * getf(p, "ripple_alpha")
	for i in m:
		if i % rp_step != 0:
			continue
		var lf: float = float(lives[i])
		if lf <= 0.01:
			continue
		var h := hash_f(i * 19 + int(seed * 3.0) + 7)
		var r := (rp_r + rp_spd * sa[i]) * (0.75 + 0.5 * h)
		var a := rp_a * lf * lf
		c.draw_arc(sp[i], r, 0.0, TAU, 30, Color(foam.r, foam.g, foam.b, a), 1.0 + h * 0.8)
		c.draw_arc(sp[i], r * 0.58, 0.0, TAU, 24,
			Color(foam.r, foam.g, foam.b, a * 0.55), 1.0)

	# 5) 焦散高光丝
	var ca_chance := getf(p, "caustic_chance")
	var ca_alpha := alpha * getf(p, "caustic_alpha")
	var ca_len := getf(p, "caustic_len_max")
	var ca_pts := PackedVector2Array()
	var ca_cols := PackedColorArray()
	for i in m:
		if i % 2 != 0:
			continue
		var lf: float = float(lives[i])
		if lf <= 0.02:
			continue
		var h := hash_f(i * 11 + int(seed * 5.0))
		if h < 1.0 - ca_chance:
			continue
		var dir := tangent(sp, i)
		var nrm := Vector2(-dir.y, dir.x)
		var off := nrm * (float(widths[i]) * (h * 1.7 - 0.85))
		var ln := lerpf(ca_len * 0.25, ca_len, h)
		var a := ca_alpha * lf * (0.35 + 0.65 * h)
		var mid := sp[i] + off + dir * ln * 0.5 + nrm * (h * 2.0 - 1.0) * 2.4
		ca_pts.append(sp[i] + off)
		ca_pts.append(mid)
		ca_cols.append(Color(foam.r, foam.g, foam.b, a))
		ca_pts.append(mid)
		ca_pts.append(sp[i] + off + dir * ln)
		ca_cols.append(Color(foam.r, foam.g, foam.b, a * 0.8))
	if ca_pts.size() >= 2:
		c.draw_multiline_colors(ca_pts, ca_cols, 1.4)

	# 6) 泡沫团：随年龄向外飘散并缩小消失
	var fo_step := maxi(geti(p, "foam_step"), 1)
	var fo_chance := getf(p, "foam_chance")
	var fo_alpha := alpha * getf(p, "foam_alpha")
	var fo_size := getf(p, "foam_size_max")
	var fo_spread := getf(p, "foam_spread")
	var fo_c := PackedVector2Array()
	var fo_r := PackedFloat32Array()
	var fo_col := PackedColorArray()
	for i in m:
		if i % fo_step != 0:
			continue
		var lf: float = float(lives[i])
		if lf <= 0.02:
			continue
		var h := hash_f(i * 7 + int(seed * 13.0) + 51)
		if h < 1.0 - fo_chance:
			continue
		var dir := tangent(sp, i)
		var nrm := Vector2(-dir.y, dir.x)
		var cluster := 2 + int(h * 2.9)
		for k in cluster:
			var hk := hash_f(i * 31 + k * 13 + int(seed * 7.0))
			var side := 1.0 if hk > 0.5 else -1.0
			var pos := sp[i] \
				+ nrm * (float(widths[i]) * 0.55 + hk * fo_spread + spread * sa[i] * 0.5) * side \
				+ dir * (hk * 2.0 - 1.0) * 4.0
			var r := lerpf(fo_size * 0.28, fo_size, hk) * (0.35 + 0.65 * lf)
			fo_c.append(pos)
			fo_r.append(r)
			fo_col.append(Color(foam.r, foam.g, foam.b, fo_alpha * lf * (0.4 + 0.6 * hk)))
			fo_c.append(pos)
			fo_r.append(r * 0.45)
			fo_col.append(Color(foam.r, foam.g, foam.b, fo_alpha * lf * 0.5))
	batch_circles(c, fo_c, fo_r, fo_col, 7)

	# 7) 接触切痕：柔和亮痕，两端随锥化淡入淡出，不再是锐利硬线
	var cut_life := getf(p, "cut_life")
	var cut_a := alpha * getf(p, "cut_alpha")
	var cut_w := getf(p, "cut_width")
	var cut_pts := PackedVector2Array()
	var cut_cols := PackedColorArray()
	var cut_seg_w := cut_w
	for i in m - 1:
		var cl0 := life_of(sa[i], cut_life, 1.2)
		var cl1 := life_of(sa[i + 1], cut_life, 1.2)
		if cl0 <= 0.01 and cl1 <= 0.01:
			continue
		var t0 := float(i) / float(m - 1)
		var t1 := float(i + 1) / float(m - 1)
		# 端点淡出因子（与主带锥化同源，起点不再突兀）
		var f0 := smoothstep(0.0, head_soft, t0) * smoothstep(0.0, head_soft, 1.0 - t0)
		var f1 := smoothstep(0.0, head_soft, t1) * smoothstep(0.0, head_soft, 1.0 - t1)
		var a0 := cut_a * cl0 * f0
		var a1 := cut_a * cl1 * f1
		if a0 <= 0.004 and a1 <= 0.004:
			continue
		cut_pts.append(sp[i])
		cut_pts.append(sp[i + 1])
		cut_cols.append(Color(foam.r, foam.g, foam.b, (a0 + a1) * 0.5))
	if cut_pts.size() >= 2:
		c.draw_multiline_colors(cut_pts, cut_cols, maxf(cut_seg_w, 0.6))

	# 8) 脚印：沿路径按间隔的离散落点，左右交错，椭圆压扁并按行进方向旋转
	var pr_step := maxi(geti(p, "print_step"), 1)
	if pr_step > 0 and getf(p, "print_alpha") > 0.001:
		var pr_size := getf(p, "print_size")
		var pr_stag := getf(p, "print_stagger")
		var pr_a := alpha * getf(p, "print_alpha")
		var pr_squash := clampf(getf(p, "print_squash"), 0.1, 1.0)
		var pr_life := getf(p, "print_life")
		var pr_ring := getf(p, "print_ring")
		var idx := 0
		for i in m:
			if i % pr_step != 0:
				continue
			idx += 1
			var plf := life_of(sa[i], pr_life, curve)
			if plf <= 0.01:
				continue
			var dir := tangent(sp, i)
			var nrm := Vector2(-dir.y, dir.x)
			var side := 1.0 if idx % 2 == 0 else -1.0
			var h := hash_f(i * 37 + int(seed * 11.0) + 17)
			var ctr := sp[i] + nrm * pr_stag * side + dir * (h * 2.0 - 1.0) * 2.0
			# 随年龄膨大一点（水印扩散）
			var rr := pr_size * (0.85 + 0.35 * (1.0 - plf)) * (0.85 + 0.3 * h)
			# 椭圆：沿行进方向拉长，法向压扁
			var ang := dir.angle()
			var pts_e := PackedVector2Array()
			var cols_e := PackedColorArray()
			var col_e := Color(water.r, water.g, water.b, pr_a * plf)
			var segs := 18
			for k in segs:
				var th := TAU * float(k) / float(segs)
				var lp := Vector2(cos(th) * rr, sin(th) * rr * pr_squash)
				pts_e.append(ctr + lp.rotated(ang))
				cols_e.append(col_e)
			c.draw_polygon(pts_e, cols_e)
			# 印记外圈泡沫环
			if pr_ring > 0.002:
				var ring := PackedVector2Array()
				for k in segs + 1:
					var th2 := TAU * float(k) / float(segs)
					var lp2 := Vector2(cos(th2) * rr * 1.06, sin(th2) * rr * pr_squash * 1.06)
					ring.append(ctr + lp2.rotated(ang))
				c.draw_polyline(ring,
					Color(foam.r, foam.g, foam.b, pr_a * plf * pr_ring * 1.6), 1.0 + h * 0.6)
