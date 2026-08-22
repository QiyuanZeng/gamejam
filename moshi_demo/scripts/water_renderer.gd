class_name WaterRenderer
extends RefCounted
## 水体尾迹渲染器（静态，纯函数）—— 飞鸟浮空掠过水面的流体痕迹。
## 局内划线、地面拓印、F1 编辑器共用同一套参数（current，来自 user://water_style.json）。
##
## 动态：每个采样点带独立年龄（秒）。年龄推进 → 切痕淡出、V 形散波向外扩张、
## 涟漪环扩大变淡、泡沫消散。尾部（最早落点）先消失，形成掠过后逐渐愈合的水面。
## 参数以 Dictionary 传入；传空字典则用 current，键缺失时回退 DEFAULTS。

const DEFAULTS := {
	# —— 接触切痕（掠水瞬时亮痕，柔和不锐利）
	"cut_width": 2.4,
	"cut_alpha": 0.42,
	"cut_life": 0.55,
	# —— 水体尾迹带
	"width_start": 9.0,
	"width_end": 3.0,
	"width_taper": 0.8,
	"head_soft": 0.22,
	"spread_speed": 26.0,
	"body_alpha": 0.30,
	"halo_scale": 1.9,
	"halo_alpha": 0.16,
	"edge_jitter": 0.20,
	"wobble_amp": 0.8,
	"wobble_freq": 14.0,
	"smooth_iters": 3,
	# —— 脚印（分段落点，踩水的离散印记）
	"print_step": 13,
	"print_size": 7.5,
	"print_stagger": 7.0,
	"print_alpha": 0.34,
	"print_squash": 0.58,
	"print_life": 1.8,
	"print_ring": 0.55,
	# —— V 形散波（开尔文尾波，掠水标志）
	"wake_angle": 0.34,
	"wake_speed": 60.0,
	"wake_alpha": 0.55,
	"wake_crest": 1.6,
	"wake_arms": 2,
	# —— 焦散高光
	"caustic_chance": 0.6,
	"caustic_alpha": 0.45,
	"caustic_len_max": 18.0,
	# —— 泡沫
	"foam_step": 3,
	"foam_chance": 0.7,
	"foam_alpha": 0.8,
	"foam_size_max": 2.8,
	"foam_spread": 10.0,
	# —— 扩散涟漪环
	"ripple_step": 20,
	"ripple_radius": 10.0,
	"ripple_speed": 46.0,
	"ripple_alpha": 0.34,
	# —— 生命周期
	"life_time": 2.6,
	"fade_curve": 1.5,
	# —— 配色（浅蓝白水面）
	"water_color": Color("#A8C8E0"),
	"foam_color": Color("#FFFFFF"),
	"surface_color": Color("#DDE9F3"),
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

## 带顶点色的缎带（逐段四边形，避免自交三角化失败，且支持沿路径渐隐）
static func ribbon_gradient(c: CanvasItem, pts: PackedVector2Array, widths: Array,
		cols: Array, scale: float, jitter: float, seed: float) -> void:
	var m := pts.size()
	if m < 2:
		return
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for i in m:
		var dir := tangent(pts, i)
		var nrm := Vector2(-dir.y, dir.x)
		var w: float = float(widths[i]) * scale
		var h := sin(float(i) * 0.41 + seed * 3.1) * 0.55 + sin(float(i) * 0.13 + seed) * 0.45
		var j := h * w * jitter
		left.append(pts[i] + nrm * (w + j))
		right.append(pts[i] - nrm * (w - j))
	for i in m - 1:
		var c0: Color = cols[i]
		var c1: Color = cols[i + 1]
		if c0.a <= 0.003 and c1.a <= 0.003:
			continue
		# 拆成两个三角形：路径急转时四边形会自交（蝴蝶形），四边形三角化会失败
		tri(c, left[i], left[i + 1], right[i + 1], c0, c1, c1)
		tri(c, left[i], right[i + 1], right[i], c0, c1, c0)

## 单个三角形（零面积 / 非法坐标直接丢弃）
static func tri(c: CanvasItem, a: Vector2, b: Vector2, d: Vector2,
		ca: Color, cb: Color, cd: Color) -> void:
	if not (is_finite(a.x) and is_finite(a.y) and is_finite(b.x) and is_finite(b.y) \
		and is_finite(d.x) and is_finite(d.y)):
		return
	if absf((b - a).cross(d - a)) < 0.002:
		return
	c.draw_polygon(PackedVector2Array([a, b, d]), PackedColorArray([ca, cb, cd]))

## 水面底纹：浅蓝白底 + 焦散网（程序化、确定性；phase 可让底纹缓慢流动）
static func draw_water_surface(c: CanvasItem, rect: Rect2, p: Dictionary, phase := 0.0) -> void:
	if p.is_empty():
		ensure_loaded()
		p = current
	var surf := getc(p, "surface_color")
	var water := getc(p, "water_color")
	var foam := getc(p, "foam_color")
	c.draw_rect(rect, surf)
	for k in 26:
		var hx := hash_f(k * 5 + 3)
		var hy := hash_f(k * 7 + 11)
		var hr := hash_f(k * 11 + 23)
		var drift := sin(phase * 0.25 + hx * 6.28) * rect.size.x * 0.012
		var ctr := rect.position + Vector2(hx * rect.size.x + drift, hy * rect.size.y)
		var r := lerpf(rect.size.y * 0.06, rect.size.y * 0.22, hr)
		c.draw_circle(ctr, r, Color(water.r, water.g, water.b, 0.06 + hr * 0.05))
	for k in 46:
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

## 主入口：飞鸟掠水尾迹。ages[i] 为对应采样点已存在的秒数（尾部最大）。
static func draw_water_path(c: CanvasItem, pts: PackedVector2Array,
		ages: PackedFloat32Array, alpha: float, p: Dictionary = {}) -> void:
	if pts.size() < 2:
		return
	if p.is_empty():
		ensure_loaded()
		p = current
	var res := smooth_with_ages(pts, ages, maxi(geti(p, "smooth_iters"), 0))
	var sp: PackedVector2Array = res[0]
	var sa: PackedFloat32Array = res[1]
	var m := sp.size()
	if m < 2:
		return
	var seed := float(int(pts[0].x) % 977) * 0.37 + float(int(pts[0].y) % 761) * 0.11
	var water := getc(p, "water_color")
	var foam := getc(p, "foam_color")
	var life_time := getf(p, "life_time")
	var curve := getf(p, "fade_curve")
	var w_start := getf(p, "width_start")
	var w_end := getf(p, "width_end")
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
		c.draw_line(sp[i] + off, mid, Color(foam.r, foam.g, foam.b, a), 1.0 + h * 0.8)
		c.draw_line(mid, sp[i] + off + dir * ln,
			Color(foam.r, foam.g, foam.b, a * 0.8), 1.0 + h * 0.6)

	# 6) 泡沫团：随年龄向外飘散并缩小消失
	var fo_step := maxi(geti(p, "foam_step"), 1)
	var fo_chance := getf(p, "foam_chance")
	var fo_alpha := alpha * getf(p, "foam_alpha")
	var fo_size := getf(p, "foam_size_max")
	var fo_spread := getf(p, "foam_spread")
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
			c.draw_circle(pos, r, Color(foam.r, foam.g, foam.b, fo_alpha * lf * (0.4 + 0.6 * hk)))
			c.draw_circle(pos, r * 0.45, Color(foam.r, foam.g, foam.b, fo_alpha * lf * 0.5))

	# 7) 接触切痕：柔和亮痕，两端随锥化淡入淡出，不再是锐利硬线
	var cut_life := getf(p, "cut_life")
	var cut_a := alpha * getf(p, "cut_alpha")
	var cut_w := getf(p, "cut_width")
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
		var seg_w := cut_w * maxf(f0, f1)
		c.draw_line(sp[i], sp[i + 1],
			Color(foam.r, foam.g, foam.b, (a0 + a1) * 0.5), maxf(seg_w, 0.6))

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
